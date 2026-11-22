import hashlib
import io
import tempfile
import unittest
from contextlib import nullcontext
from collections import defaultdict
from pathlib import Path
from time import monotonic
from unittest.mock import Mock, patch

from fastapi.testclient import TestClient
from PIL import Image

from boipath.app import create_app
from boipath.covers import (
    CoverCache, CoverUnavailable, build_cover, cover_sources, fetch_thumbnail, thumbnail_requests,
)
from boipath.db import Database


GOOGLE_DOWNLOAD = "https://drive.google.com/uc?export=download&id=Textbook-Google"
GOVERNMENT_DOWNLOAD = "https://drive.egovcloud.gov.bd/index.php/s/TextbookGovernment/download"


def fixture_cover(color, image_format="WEBP", size=(140, 200)):
    image = io.BytesIO()
    Image.new("RGB", size, color).save(image, image_format)
    return image.getvalue()


def fixture_response(mime_type, body, status=200):
    response = Mock(status=status)
    response.getheader.side_effect = {"Content-Type": mime_type}.get
    payload = io.BytesIO(body)
    response.read.side_effect = payload.read
    response.read1.side_effect = payload.read1
    return response


class CoverTests(unittest.TestCase):
    def test_fetch_resizes_thumbnail_and_preserves_portrait_ratio(self):
        response = fixture_response("image/png", fixture_cover("purple", "PNG", (700, 1000)))
        with patch("boipath.covers.thumbnail_response", return_value=nullcontext(response)):
            result = fetch_thumbnail("https://preview.invalid", set(), monotonic() + 1)
        with Image.open(io.BytesIO(result)) as cover:
            self.assertEqual(cover.format, "WEBP")
            self.assertEqual(cover.size, (336, 480))
            red, green, blue = cover.getpixel((150, 150))
            self.assertGreater(red, 110)
            self.assertLess(green, 20)
            self.assertGreater(blue, 110)

    def test_uses_book_specific_image_endpoints_and_falls_back_between_publishers(self):
        sources = (GOVERNMENT_DOWNLOAD, GOOGLE_DOWNLOAD)
        requests = thumbnail_requests(sources)
        self.assertEqual(requests[0][0], "https://drive.google.com/thumbnail?id=Textbook-Google&sz=w480")
        self.assertIn("/publicpreview/TextbookGovernment?", requests[1][0])
        result = fixture_cover("purple")
        with patch("boipath.covers.fetch_thumbnail", side_effect=[CoverUnavailable(), result]) as fetch:
            self.assertEqual(build_cover(sources), result)
        self.assertEqual([call.args[:2] for call in fetch.call_args_list], requests)

    def test_confirmed_pdf_override_does_not_show_a_different_edition(self):
        pdf_url = "https://nctb.gov.bd/updated-edition.pdf"
        sources = cover_sources({"pdf_url": pdf_url, "source_download_urls": [GOOGLE_DOWNLOAD]})
        self.assertEqual(sources, (pdf_url,))
        with patch("boipath.covers.connect_public_https") as connect, self.assertRaises(CoverUnavailable):
            build_cover(sources)
        connect.assert_not_called()

    def test_rejects_pdf_without_reading_the_body(self):
        response = fixture_response("application/pdf", b"%PDF-1.7")
        connection = Mock()
        connection.getresponse.return_value = response
        with patch("boipath.covers.connect_public_https", return_value=connection):
            with self.assertRaises(CoverUnavailable):
                build_cover((GOOGLE_DOWNLOAD,))
        response.read.assert_not_called()
        self.assertNotIn("Range", connection.request.call_args.kwargs["headers"])

    def test_rejects_pdf_mislabeled_as_an_image_after_the_signature(self):
        response = fixture_response("image/png", b"%PDF-1.7 fake image")
        with patch("boipath.covers.thumbnail_response", return_value=nullcontext(response)):
            with self.assertRaises(CoverUnavailable):
                build_cover((GOOGLE_DOWNLOAD,))
        response.read.assert_called_once_with(12)
        response.read1.assert_not_called()

    def test_does_not_follow_a_redirect_to_the_download_path(self):
        response = Mock(status=302)
        response.getheader.return_value = GOOGLE_DOWNLOAD
        connection = Mock()
        connection.getresponse.return_value = response
        with patch("boipath.covers.connect_public_https", return_value=connection) as connect:
            with self.assertRaises(CoverUnavailable):
                build_cover((GOOGLE_DOWNLOAD,))
        connect.assert_called_once()
        connection.request.assert_called_once()

    def test_catalog_endpoint_reuses_a_previous_png_without_a_network_request(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = Database(str(Path(tmp) / "boipath.sqlite3"))
            fetch = Mock()
            covers = CoverCache(Path(tmp), fetch)
            with TestClient(create_app(db, seed_at_startup=True, covers=covers)) as client:
                book = client.get("/api/v1/books", params={"limit": 1}).json()["items"][0]
                key = hashlib.sha256("\n".join(book["source_download_urls"]).encode()).hexdigest()
                result = fixture_cover("purple", "PNG")
                (Path(tmp) / f"{key}.png").write_bytes(result)
                response = client.get(f"/api/v1/books/{book['id']}/cover")
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.headers["content-type"], "image/png")
                self.assertEqual(response.content, result)
                fetch.assert_not_called()

    def test_catalog_endpoint_uses_the_books_own_sources_and_shares_duplicate_covers(self):
        calls = []
        result = fixture_cover("purple")

        def fetch(sources):
            calls.append(sources)
            return result

        with tempfile.TemporaryDirectory() as tmp:
            db = Database(str(Path(tmp) / "boipath.sqlite3"))
            covers = CoverCache(Path(tmp) / "covers", fetch)
            with TestClient(create_app(db, seed_at_startup=True, covers=covers)) as client:
                books = "/api/v1/books"
                physics = client.get(books, params={"class_id": 10, "subject": "physics"}).json()["items"]
                for book in physics:
                    response = client.get(f"{books}/{book['id']}/cover")
                    self.assertEqual(response.status_code, 200)
                    self.assertEqual(response.headers["content-type"], "image/webp")
                    self.assertEqual(response.content, result)
                self.assertEqual(calls, [tuple(book["source_download_urls"]) for book in physics])
                self.assertNotEqual(calls[0], calls[1])
                class_one = client.get(books, params={"class_id": 1}).json()["items"]
                by_file = defaultdict(list)
                for book in class_one:
                    by_file[tuple(book["source_download_urls"])].append(book["id"])
                sources, ids = next((sources, ids) for sources, ids in by_file.items() if len(ids) > 1)
                for book_id in ids:
                    self.assertEqual(client.get(f"{books}/{book_id}/cover").status_code, 200)
                self.assertEqual(calls.count(sources), 1)
                self.assertEqual(client.get(f"{books}/missing-book/cover").status_code, 404)

    def test_unavailable_covers_allow_a_later_retry(self):
        calls = []

        def unavailable(sources):
            calls.append(sources)
            raise CoverUnavailable("Test source is unavailable")

        with tempfile.TemporaryDirectory() as tmp:
            db = Database(str(Path(tmp) / "boipath.sqlite3"))
            covers = CoverCache(Path(tmp) / "covers", unavailable)
            with TestClient(create_app(db, seed_at_startup=True, covers=covers)) as client:
                book = client.get("/api/v1/books", params={"limit": 1}).json()["items"][0]
                url = f"/api/v1/books/{book['id']}/cover"
                for _ in range(2):
                    response = client.get(url)
                    self.assertEqual(response.status_code, 503)
                    self.assertEqual(response.headers["cache-control"], "no-store")
                    self.assertEqual(response.headers["retry-after"], "60")
                self.assertEqual(len(calls), 1)
