import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from boipath.app import create_app, create_user
from boipath.catalog import SOURCE_DOWNLOAD, seed_catalog
from boipath.db import Database
from boipath.schemas import Credentials
from boipath.security import parse_official_url, verify_pdf


class ApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def setUp(self):
        url = os.environ.get("BOIPATH_TEST_DATABASE_URL") or str(Path(self.tmp.name) / f"{self._testMethodName}.sqlite3")
        self.db = Database(url)
        self.api = TestClient(create_app(self.db, verifier=self.fake_verifier))
        self.api.__enter__()
        self.addCleanup(self.api.__exit__, None, None, None)
        if self.db.postgres:
            with self.db.connect() as tx:
                tx.run("TRUNCATE classrooms, audit, reports, tokens, users, books")
        self.admin = self.account("admin", "admin")
        self.teacher = self.account("teacher", "teacher")

    @staticmethod
    def fake_verifier(url):
        if "broken" in url:
            raise ValueError("Broken fixture")
        return 1200

    def account(self, name, role):
        credentials = Credentials(email=f"{name}@example.test", password="example-test-secret")
        create_user(self.db, credentials, role)
        return self.api.post("/api/v1/auth/login", json=credentials.model_dump()).json()

    def auth(self, account=None):
        return {"Authorization": f"Bearer {(account or self.admin)['access_token']}"}

    @staticmethod
    def record(**overrides):
        return {
            "official_title": "পরীক্ষার গণিত",
            "subject_id": "mathematics",
            "class_id": 1,
            "academic_year": 2026,
            "language_version": "bn",
            "curriculum_track": "Test",
            "source_url": "https://nctb.gov.bd/example-source",
            "pdf_url": "https://nctb.gov.bd/example-fixture.pdf",
            "verification_status": "pending",
            **overrides,
        }

    def add(self, **overrides):
        response = self.api.post("/api/v1/admin/books", json=self.record(**overrides), headers=self.auth())
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["id"]

    def publish(self, book_id):
        return self.api.post(f"/api/v1/admin/books/{book_id}/verify", headers=self.auth())

    def test_catalog_and_search(self):
        first = self.add()
        second = self.add(language_version="en")
        self.add(official_title="Hidden", verification_status="draft")
        visible = self.api.get("/api/v1/books", params={"limit": 1}).json()
        self.assertEqual(visible["total"], 2)
        self.assertEqual(len(visible["items"]), 1)
        next_page = self.api.get("/api/v1/books", params={"limit": 1, "offset": 1}).json()
        self.assertNotEqual(visible["items"][0]["id"], next_page["items"][0]["id"])
        result = self.api.get("/api/v1/search", params={"q": "গণিত ২০২৬", "version": "en", "class_id": 1}).json()
        self.assertEqual([row["id"] for row in result["items"]], [second])
        self.assertEqual(self.api.get("/api/v1/search", params={"q": "mathematicz"}).json()["total"], 2)
        self.assertIsNone(self.api.get(f"/api/v1/books/{first}").json()["pdf_url"])
        self.assertEqual(len(self.api.get("/api/v1/classes").json()), 12)

    def test_seed_covers_every_class_and_keeps_existing_book_edits(self):
        seed_catalog(self.db)
        books = "/api/v1/books"
        self.assertEqual(self.api.get(books).json()["total"], 269)
        for grade, count in enumerate((6, 6, 18, 18, 18, 44, 44, 44, 66, 66, 5, 5), 1):
            result = self.api.get(books, params={"class_id": grade, "limit": 100}).json()
            self.assertEqual(result["total"], count, f"Class {grade}")
            self.assertTrue(all(row["pdf_url"] is None for row in result["items"]))
        physics = self.api.get(books, params={"class_id": 10, "subject": "physics", "version": "en"}).json()
        self.assertEqual([row["official_title"] for row in physics["items"]], ["Physics"])
        book_id = physics["items"][0]["id"]
        with self.db.connect() as tx:
            tx.run("UPDATE books SET verification_status='archived' WHERE id=?", (book_id,))
        seed_catalog(self.db)
        self.assertEqual(self.api.get(books).json()["total"], 268)
        self.assertEqual(self.api.get(f"{books}/{book_id}").status_code, 404)

    def test_seeded_downloads_are_book_specific_and_legacy_records_gain_links(self):
        seed_catalog(self.db)
        path = "/api/v1/books"
        catalog = [row for offset in (0, 100, 200) for row in self.api.get(
            path, params={"limit": 100, "offset": offset}).json()["items"]]
        self.assertEqual(len(catalog), 269)
        for row in catalog:
            urls = row["source_download_urls"]
            self.assertTrue(urls, row["id"])
            self.assertTrue(all(SOURCE_DOWNLOAD.fullmatch(url) for url in urls))
            self.assertIsNone(row["pdf_url"])
        results = self.api.get(path, params={"class_id": 10, "subject": "physics"}).json()["items"]
        by_language = {row["language_version"]: row for row in results}
        self.assertNotEqual(by_language["bn"]["source_download_urls"], by_language["en"]["source_download_urls"])

        book_id = by_language["bn"]["id"]
        book_path = f"{path}/{book_id}"
        with self.db.connect() as tx:
            tx.run("UPDATE books SET source_download_links=NULL WHERE id=?", (book_id,))
        self.assertEqual(self.api.get(book_path).json()["source_download_urls"], [])
        seed_catalog(self.db)
        self.assertEqual(self.api.get(book_path).json()["source_download_urls"],
                         by_language["bn"]["source_download_urls"])

        with self.db.connect() as tx:
            tx.run("UPDATE books SET verification_status='unavailable' WHERE id=?", (book_id,))
        self.assertEqual(self.api.get(book_path).json()["source_download_urls"], [])

    def test_shared_book_is_discoverable_and_rejects_invalid_grade_ranges(self):
        book_id = self.add(class_id=11, class_end_id=12)
        options = {"q": "class 12", "class_id": 12}
        books = self.api.get("/api/v1/search", params=options).json()
        self.assertEqual([row["id"] for row in books["items"]], [book_id])
        route = f"/api/v1/admin/books/{book_id}"
        result = self.api.patch(route, json=self.record(class_id=11), headers=self.auth())
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json()["class_end_id"], 12)
        invalid = self.api.patch(route, json=self.record(class_id=11, class_end_id=10), headers=self.auth())
        self.assertEqual(invalid.status_code, 422)

    def test_publication_audit_and_archive(self):
        book_id = self.add()
        response = self.publish(book_id)
        self.assertEqual(response.status_code, 200, response.text)
        row = self.api.get(f"/api/v1/books/{book_id}").json()
        self.assertEqual(row["file_size"], 1200)
        self.assertIsNotNone(row["last_verified_at"])
        self.assertEqual(row["pdf_url"], self.record()["pdf_url"])
        self.assertEqual(self.api.get("/api/v1/admin/stats", headers=self.auth()).json()["verified"], 1)
        archive = self.api.delete(f"/api/v1/admin/books/{book_id}", headers=self.auth())
        self.assertEqual(archive.status_code, 200)
        self.assertEqual(self.api.get(f"/api/v1/books/{book_id}").status_code, 404)
        audit = self.api.get("/api/v1/admin/audit", headers=self.auth()).json()
        self.assertEqual([row["action"] for row in audit], ["archive", "verify", "create"])

    def test_broken_link_stays_pending_and_report_can_be_resolved(self):
        book_id = self.add(pdf_url="https://nctb.gov.bd/broken.pdf")
        self.assertEqual(self.publish(book_id).status_code, 422)
        self.assertIsNone(self.api.get(f"/api/v1/books/{book_id}").json()["pdf_url"])
        report = self.api.post("/api/v1/reports", json={"textbook_id": book_id,
                               "description": "PDF failed", "issue_type": "broken_link"})
        self.assertEqual(report.status_code, 201)
        report_id = report.json()["id"]
        self.assertEqual(self.api.patch(f"/api/v1/admin/reports/{report_id}/resolve",
                                        headers=self.auth()).status_code, 200)
        self.assertEqual(self.api.get("/api/v1/admin/reports", headers=self.auth()).json()[0]["status"], "resolved")

    def test_permission_duplicate_and_unverified_publishing(self):
        route = "/api/v1/admin/books"
        self.assertEqual(self.api.post(route, json=self.record()).status_code, 401)
        self.assertEqual(self.api.post(route, json=self.record(), headers=self.auth(self.teacher)).status_code, 403)
        self.assertEqual(self.api.post(route, json=self.record(verification_status="verified"),
                                       headers=self.auth()).status_code, 422)
        self.add()
        self.assertEqual(self.api.post(route, json=self.record(), headers=self.auth()).status_code, 409)
        self.assertEqual(self.api.post(route, json=self.record(pdf_url="https://example.test/file"),
                                       headers=self.auth()).status_code, 422)

    def test_registration_policy_and_report_rate_limit(self):
        creds = {"email": "open@example.test", "password": "example-test-secret"}
        with patch.dict(os.environ, {"BOIPATH_TEACHER_REGISTRATION": "false"}):
            self.assertEqual(self.api.post("/api/v1/auth/register", json=creds).status_code, 403)
        with patch.dict(os.environ, {"BOIPATH_TEACHER_REGISTRATION": "true"}):
            response = self.api.post("/api/v1/auth/register", json={**creds, "role": "admin"})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()["role"], "teacher")
        book_id = self.add()
        report = {"textbook_id": book_id, "description": "Link report", "issue_type": "other"}
        for _ in range(6):
            self.assertEqual(self.api.post("/api/v1/reports", json=report).status_code, 201)
        limited = self.api.post("/api/v1/reports", json=report)
        self.assertEqual(limited.status_code, 429)
        self.assertGreater(int(limited.headers["Retry-After"]), 0)

    def test_refresh_rotates_and_logout_revokes(self):
        old = self.admin
        data = {"refresh_token": old["refresh_token"]}
        item = self.api.post("/api/v1/auth/refresh", json=data)
        self.assertEqual(item.status_code, 200)
        new = item.json()
        self.assertEqual(self.api.post("/api/v1/auth/refresh", json=data).status_code, 401)
        self.assertEqual(self.api.get("/api/v1/admin/books", headers=self.auth(old)).status_code, 401)
        self.assertEqual(self.api.post("/api/v1/auth/logout", headers=self.auth(new)).status_code, 200)
        self.assertEqual(self.api.get("/api/v1/admin/books", headers=self.auth(new)).status_code, 401)

    def test_live_session_permissions_and_follow(self):
        book = self.add()
        base = "/api/v1/classrooms"
        data = {"textbook_id": book, "page": 3}
        self.assertEqual(self.api.post(base, json=data, headers=self.auth(self.teacher)).status_code, 404)
        self.assertEqual(self.publish(book).status_code, 200)
        self.assertEqual(self.api.post(base, json=data, headers=self.auth()).status_code, 403)
        response = self.api.post(base, json=data, headers=self.auth(self.teacher))
        self.assertEqual(response.status_code, 201, response.text)
        path = f"{base}/{response.json()['code']}"
        self.assertEqual(self.api.get(path).json()["current_page"], 3)
        other = self.account("another", "teacher")
        self.assertEqual(self.api.patch(path + "/page", json={"page": 5}, headers=self.auth(other)).status_code, 404)
        with self.api.websocket_connect(path + "/ws") as websocket:
            self.assertEqual(websocket.receive_json()["current_page"], 3)
            self.assertEqual(self.api.patch(path + "/page", json={"page": 5},
                                            headers=self.auth(self.teacher)).status_code, 200)
            self.assertEqual(websocket.receive_json()["current_page"], 5)
            self.assertEqual(self.api.post(path + "/end", headers=self.auth(self.teacher)).status_code, 200)
            self.assertEqual(websocket.receive_json()["status"], "ended")

    def test_live_session_expiration_and_origin_guards(self):
        book = self.add()
        self.publish(book)
        base = "/api/v1/classrooms"
        response = self.api.post(base, json={"textbook_id": book, "page": 1},
                                 headers=self.auth(self.teacher))
        code = response.json()["code"]
        with self.db.connect() as tx:
            tx.run("UPDATE classrooms SET expires_at=? WHERE code=?", (int(time.time()) - 1, code))
        path = f"{base}/{code}"
        self.assertEqual(self.api.get(path).json()["status"], "expired")
        self.assertEqual(self.api.patch(path + "/page", json={"page": 4}, headers=self.auth(self.teacher)).status_code, 409)
        with self.assertRaises(WebSocketDisconnect):
            with self.api.websocket_connect(path + "/ws", headers={"Origin": "https://example.test"}):
                self.fail("An unapproved origin was accepted")
        with self.api.websocket_connect(path + "/ws") as websocket:
            self.assertEqual(websocket.receive_json()["status"], "expired")


class PdfValidationTests(unittest.TestCase):
    def test_denies_nonapproved_urls(self):
        for url in ["http://nctb.gov.bd/test.pdf", "https://nctb.gov.bd@127.0.0.1/test",
                    "https://nctb.gov.bd:8443/test", "https://nctb.gov.bd//evil.test/test",
                    "https://nctb.gov.bd.example.test/file", "https://nctb.gov.bd/test#fragment"]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                parse_official_url(url, {"nctb.gov.bd"})

    @patch("boipath.security.PinnedHTTPSConnection")
    @patch("boipath.security.socket.getaddrinfo")
    def test_denies_private_dns_answers_before_connecting(self, dns, connection):
        dns.return_value = [(None, None, None, None, ("192.168.1.100", 443))]
        with self.assertRaisesRegex(ValueError, "disallowed address"):
            verify_pdf("https://nctb.gov.bd/file.pdf")
        connection.assert_not_called()

    @patch("boipath.security.PinnedHTTPSConnection")
    @patch("boipath.security.socket.getaddrinfo")
    def test_validates_partial_pdf_and_does_not_follow_redirects(self, dns, connect):
        dns.return_value = [(None, None, None, None, ("93.184.216.34", 443))]
        connection = connect.return_value
        response = connection.getresponse.return_value
        response.status = 302
        with self.assertRaises(ValueError):
            verify_pdf("https://nctb.gov.bd/file.pdf")
        connect.assert_called_once_with("nctb.gov.bd", "93.184.216.34")
        response.status = 206
        response.read.return_value = b"%PDF-1.7"
        response.getheader.return_value = "bytes 0-15/600"
        self.assertEqual(verify_pdf("https://nctb.gov.bd/file.pdf"), 600)
