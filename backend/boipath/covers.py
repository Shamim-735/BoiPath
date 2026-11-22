"""Fetch and cache publisher thumbnail images for textbook cards."""
import hashlib
import http.client
import io
import logging
import os
import tempfile
import time
from collections import OrderedDict
from contextlib import contextmanager
from pathlib import Path
from threading import BoundedSemaphore, Lock
from urllib.parse import parse_qs, urlencode, urljoin

from .catalog import SOURCE_DOWNLOAD
from .security import connect_public_https, parse_official_url

LOGGER = logging.getLogger(__name__)
GOOGLE_DRIVE = "drive.google.com"
GOOGLE_IMAGE_HOSTS = {"lh3.googleusercontent.com", "lh3.google.com"}
GOVERNMENT_DRIVE = "drive.egovcloud.gov.bd"
IMAGE_TYPES = {"image/png", "image/jpeg", "image/webp"}
MAX_BYTES = 2 * 1024 * 1024
THUMBNAIL_SIZE = 480


class CoverUnavailable(Exception):
    pass


def thumbnail_requests(sources):
    google = []
    government = []
    for source in sources:
        if not SOURCE_DOWNLOAD.fullmatch(source):
            continue
        target = parse_official_url(source, {GOOGLE_DRIVE, GOVERNMENT_DRIVE})
        if target.hostname == GOOGLE_DRIVE:
            file_id = parse_qs(target.query)["id"][0]
            query = urlencode({"id": file_id, "sz": f"w{THUMBNAIL_SIZE}"})
            google.append((f"https://{GOOGLE_DRIVE}/thumbnail?{query}", {GOOGLE_DRIVE} | GOOGLE_IMAGE_HOSTS))
        else:
            token = target.path.split("/")[-2]
            query = urlencode({"file": "/", "x": THUMBNAIL_SIZE, "y": THUMBNAIL_SIZE, "a": "true"})
            government.append((
                f"https://{GOVERNMENT_DRIVE}/index.php/apps/files_sharing/publicpreview/{token}?{query}",
                {GOVERNMENT_DRIVE},
            ))
    return google + government


@contextmanager
def thumbnail_response(url, hosts, deadline):
    headers = {"Accept": "image/webp,image/jpeg,image/png", "Accept-Encoding": "identity"}
    preview_path = parse_official_url(url, hosts).path.removeprefix("/index.php")
    for _ in range(3):
        target = parse_official_url(url, hosts)
        if (target.hostname not in GOOGLE_IMAGE_HOSTS
                and target.path.removeprefix("/index.php") != preview_path):
            raise CoverUnavailable("Redirect left the publisher preview endpoint")
        connection = connect_public_https(target)
        try:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise CoverUnavailable("Cover source timed out")
            connection.timeout = remaining
            path = target.path + ("?" + target.query if target.query else "")
            connection.request("GET", path, headers=headers)
            response = connection.getresponse()
            if response.status in (301, 302, 303, 307, 308):
                location = response.getheader("Location")
                if not location:
                    raise CoverUnavailable("Missing thumbnail redirect location")
                url = urljoin(url, location)
                continue
            yield response
            return
        finally:
            connection.close()
    raise CoverUnavailable("Too many thumbnail redirects")


def fetch_thumbnail(url, hosts, deadline):
    from PIL import Image

    with thumbnail_response(url, hosts, deadline) as response:
        mime_type = response.getheader("Content-Type", "").split(";", 1)[0].strip().lower()
        if response.status != 200 or mime_type not in IMAGE_TYPES:
            raise CoverUnavailable("Publisher did not return a thumbnail image")
        size = response.getheader("Content-Length", "")
        if size.isdecimal() and int(size) > MAX_BYTES:
            raise CoverUnavailable("Publisher thumbnail is too large")
        data = bytearray(response.read(12))
        if not (data.startswith((b"\x89PNG\r\n\x1a\n", b"\xff\xd8\xff"))
                or (data.startswith(b"RIFF") and data[8:12] == b"WEBP")):
            raise CoverUnavailable("Publisher thumbnail has an invalid image signature")
        while chunk := response.read1(64 * 1024):
            if time.monotonic() >= deadline or len(data) + len(chunk) > MAX_BYTES:
                raise CoverUnavailable("Publisher thumbnail exceeded the request budget")
            data.extend(chunk)

    with Image.open(io.BytesIO(data), formats=("JPEG", "PNG", "WEBP")) as image:
        if image.width * image.height > 4_000_000:
            raise CoverUnavailable("Publisher thumbnail dimensions are too large")
        image.thumbnail((THUMBNAIL_SIZE, THUMBNAIL_SIZE), Image.Resampling.LANCZOS)
        output = io.BytesIO()
        image.convert("RGB").save(output, format="WEBP", quality=84)
        return output.getvalue()


def cover_sources(book):
    sources = [url for url in book["source_download_urls"] if SOURCE_DOWNLOAD.fullmatch(url)]
    if pdf_url := book.get("pdf_url"):
        if pdf_url not in sources:
            return (pdf_url,)
        sources.insert(0, pdf_url)
    return tuple(dict.fromkeys(sources))


def build_cover(sources):
    from PIL import Image

    deadline = time.monotonic() + 7
    failures = (CoverUnavailable, OSError, ValueError, http.client.HTTPException, Image.DecompressionBombError)
    for url, hosts in thumbnail_requests(sources):
        now = time.monotonic()
        if now >= deadline:
            break
        try:
            return fetch_thumbnail(url, hosts, min(deadline, now + 3.5))
        except failures as error:
            LOGGER.debug("Publisher thumbnail unavailable: %s", error)
    raise CoverUnavailable("No publisher thumbnail is available")


class CoverCache:
    def __init__(self, directory=None, fetch=build_cover):
        self.directory = Path(directory or os.getenv("BOIPATH_COVER_CACHE", ".cover-cache"))
        self.fetch = fetch
        self.jobs = BoundedSemaphore(6)
        self.locks = [Lock() for _ in range(64)]
        self.failures = OrderedDict()
        self.failure_guard = Lock()

    def get(self, sources):
        key = hashlib.sha256("\n".join(sources).encode()).hexdigest()
        path = self.directory / f"{key}.webp"
        legacy = self.directory / f"{key}.png"
        lock = self.locks[int(key[:2], 16) % len(self.locks)]
        with lock:
            if path.is_file():
                return path
            if legacy.is_file():
                return legacy
            with self.failure_guard:
                if self.failures.get(key, 0) > time.monotonic():
                    raise CoverUnavailable("Waiting to retry book cover")
            if not self.jobs.acquire(timeout=4):
                raise CoverUnavailable("Cover requests are busy")
            try:
                image = self.fetch(sources)
            except (CoverUnavailable, ImportError):
                with self.failure_guard:
                    self.failures[key] = time.monotonic() + 60
                    self.failures.move_to_end(key)
                    if len(self.failures) > 512:
                        self.failures.popitem(last=False)
                raise
            finally:
                self.jobs.release()
            self.directory.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=self.directory, delete=False) as file:
                partial = Path(file.name)
                file.write(image)
            try:
                partial.replace(path)
            finally:
                partial.unlink(missing_ok=True)
            return path
