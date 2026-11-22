#!/usr/bin/env python3
"""Generate offline 480px RGB JPEG book covers from starter_catalog.json."""

from __future__ import annotations

import io
import json
import re
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

import pypdfium2 as pdfium
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = ROOT / "apps" / "flutter_app" / "assets" / "starter_catalog.json"
COVERS_DIR = ROOT / "apps" / "flutter_app" / "assets" / "covers"
TARGET_WIDTH = 480
USER_AGENT = "BoiPathCoverGenerator/1.0"


def extract_drive_file_id(url: str) -> str | None:
    parsed = urllib.parse.urlparse(url)
    if "drive.google.com" not in parsed.netloc:
        return None
    qs = urllib.parse.parse_qs(parsed.query)
    if "id" in qs and qs["id"]:
        return qs["id"][0]
    match = re.search(r"/d/([^/]+)", parsed.path)
    return match.group(1) if match else None


def download_bytes(url: str, timeout: int = 30) -> tuple[str, bytes]:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        content_type = resp.headers.get("Content-Type", "")
        return content_type, resp.read()


def save_cover_image(img: Image.Image, out_path: Path) -> None:
    rgb = img.convert("RGB")
    if rgb.width != TARGET_WIDTH:
        height = max(1, round(rgb.height * TARGET_WIDTH / rgb.width))
        rgb = rgb.resize((TARGET_WIDTH, height), Image.Resampling.LANCZOS)
    rgb.save(out_path, "JPEG", quality=82, optimize=True)


def try_drive_thumbnail(urls: list[str], out_path: Path) -> bool:
    for url in urls:
        file_id = extract_drive_file_id(url)
        if not file_id:
            continue
        query = urllib.parse.urlencode({"id": file_id, "sz": "w800"})
        thumb_url = urllib.parse.urlunparse(
            ("https", "drive.google.com", "/thumbnail", "", query, "")
        )
        try:
            content_type, data = download_bytes(thumb_url)
            if "image" in content_type.lower() and len(data) > 5000:
                with Image.open(io.BytesIO(data)) as img:
                    save_cover_image(img, out_path)
                return True
        except Exception as exc:
            print(f"  Thumbnail failed ({file_id}): {exc}")
    return False


def try_pdf_fallback(urls: list[str], out_path: Path) -> bool:
    ordered = sorted(urls, key=lambda u: 0 if "egovcloud" in u.lower() else 1)
    for url in ordered:
        tmp_path: Path | None = None
        try:
            _, data = download_bytes(url, timeout=60)
            if not data.startswith(b"%PDF"):
                continue
            with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
                tmp.write(data)
                tmp_path = Path(tmp.name)
            pdf = pdfium.PdfDocument(str(tmp_path))
            try:
                page = pdf[0]
                bitmap = page.render(scale=1.5)
                img = bitmap.to_pil()
                save_cover_image(img, out_path)
                return True
            finally:
                pdf.close()
        except Exception as exc:
            print(f"  PDF fallback failed ({url}): {exc}")
        finally:
            if tmp_path is not None and tmp_path.exists():
                tmp_path.unlink()
    return False


def main() -> None:
    COVERS_DIR.mkdir(parents=True, exist_ok=True)
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    for book in catalog:
        book_id = book.get("id")
        if not book_id:
            continue
        out_path = COVERS_DIR / f"{book_id}.jpg"
        if out_path.exists():
            print(f"Skipping existing cover: {out_path.name}")
            continue
        urls = book.get("source_download_urls") or []
        print(f"Generating cover for {book_id}...")
        if try_drive_thumbnail(urls, out_path):
            print(f"  Saved from Google Drive thumbnail: {out_path.name}")
        elif try_pdf_fallback(urls, out_path):
            print(f"  Saved from PDF page 0: {out_path.name}")
        else:
            print(f"  Failed to generate cover for {book_id}")


if __name__ == "__main__":
    main()
