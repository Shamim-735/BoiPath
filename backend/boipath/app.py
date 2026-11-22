import http.client
import json
import os
import time
from contextlib import asynccontextmanager
from uuid import uuid4

from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .catalog import BOOK_IDENTITY, seed_catalog
from .classrooms import install_classrooms
from .covers import CoverCache, CoverUnavailable, cover_sources
from .db import default_database, integrity_error, now
from .schemas import BookInput, Credentials, Refresh, Report
from .search import matches
from .security import (
    DUMMY_HASH, NCTB_HOSTS, RateLimit, issue_tokens, parse_official_url, password_hash,
    password_matches, pdf_hosts, token_hash, verify_pdf,
)

BOOKS = """SELECT b.*, s.name_en AS subject_en, s.name_bn AS subject_bn,
    c.name_en AS class_en, c.name_bn AS class_bn
    FROM books b JOIN subjects s ON s.id=b.subject_id JOIN class_levels c ON c.id=b.class_id"""
PUBLIC = "b.verification_status IN ('verified','pending','unavailable')"
BEARER = HTTPBearer(auto_error=False)


def public_book(row):
    result = dict(row)
    links = result.pop("source_download_links", None)
    result["source_download_urls"] = json.loads(links) if links and row["verification_status"] in ("verified", "pending") else []
    if row["verification_status"] != "verified":
        result["pdf_url"] = None
    return result


def create_app(database=None, verifier=verify_pdf, *, seed_at_startup=False, covers=None):
    db = database or default_database()
    limits = RateLimit()
    cover_cache = covers if covers is not None else CoverCache()

    @asynccontextmanager
    async def lifespan(_app):
        db.migrate()
        if seed_at_startup:
            seed_catalog(db)
        yield

    app = FastAPI(title="BoiPath API", version="0.1.0", lifespan=lifespan)
    origins = [origin.strip() for origin in os.getenv("BOIPATH_ORIGINS", "").split(",") if origin.strip()]
    app.add_middleware(CORSMiddleware, allow_origins=origins, allow_methods=["GET", "POST", "PATCH", "DELETE"],
                       allow_headers=["Authorization", "Content-Type"])

    def throttle(request, key, count, seconds=60):
        limits.check(key, request.client.host if request.client else "unknown", count, seconds)

    def require_user(credentials: HTTPAuthorizationCredentials | None = Depends(BEARER)):
        if credentials is None or len(credentials.credentials) > 128:
            raise HTTPException(401, "Sign in required", headers={"WWW-Authenticate": "Bearer"})
        with db.connect() as tx:
            user = tx.one("""SELECT u.id,u.role,t.family FROM users u JOIN tokens t ON t.user_id=u.id
                WHERE t.token_hash=? AND t.kind='access' AND t.expires_at>?""",
                          (token_hash(credentials.credentials), int(time.time())))
        if user is None:
            raise HTTPException(401, "Session expired", headers={"WWW-Authenticate": "Bearer"})
        return user

    def require_admin(user=Depends(require_user)):
        if user["role"] != "admin":
            raise HTTPException(403, "Administrator role required")
        return user

    def audit(tx, user, action, book_id):
        tx.run("INSERT INTO audit VALUES (?,?,?,?,?)", (str(uuid4()), user["id"], action, book_id, now()))

    @app.get("/health")
    def health():
        return {"status": "ok"}

    @app.get("/api/v1/books")
    @app.get("/api/v1/search")
    def books(q: str = Query("", max_length=160), year: int | None = None,
              class_id: int | None = Query(None, ge=1, le=12),
              version: str | None = Query(None, pattern="^(bn|en)$"),
              subject: str | None = Query(None, max_length=64),
              track: str | None = Query(None, max_length=100),
              offset: int = Query(0, ge=0, le=100000), limit: int = Query(30, ge=1, le=100)):
        conditions, args = [PUBLIC], []
        for column, value in (("academic_year", year), ("language_version", version),
                              ("subject_id", subject), ("curriculum_track", track)):
            if value is not None:
                conditions.append(f"b.{column}=?")
                args.append(value)
        if class_id is not None:
            conditions.append("b.class_id<=? AND COALESCE(b.class_end_id,b.class_id)>=?")
            args.extend((class_id, class_id))
        sql = BOOKS + " WHERE " + " AND ".join(conditions) + " ORDER BY b.official_title,b.id"
        with db.connect() as tx:
            if q.strip():
                rows = [row for row in tx.all(sql, args) if matches(row, q)]
                return {"items": [public_book(row) for row in rows[offset:offset + limit]],
                        "total": len(rows), "offset": offset}
            total = tx.one("SELECT COUNT(*) AS n FROM (" + sql + ") result", args)["n"]
            rows = tx.all(sql + " LIMIT ? OFFSET ?", (*args, limit, offset))
        return {"items": [public_book(row) for row in rows], "total": total, "offset": offset}

    @app.get("/api/v1/books/{book_id}")
    def book(book_id: str):
        with db.connect() as tx:
            row = tx.one(BOOKS + " WHERE " + PUBLIC + " AND b.id=?", (book_id,))
        if row is None:
            raise HTTPException(404, "Textbook not found")
        return public_book(row)

    @app.get("/api/v1/books/{book_id}/cover")
    def textbook_cover(book_id: str):
        with db.connect() as tx:
            row = tx.one(BOOKS + " WHERE " + PUBLIC + " AND b.id=?", (book_id,))
        sources = cover_sources(public_book(row)) if row else ()
        if not sources:
            raise HTTPException(404, "Book cover unavailable")
        try:
            path = cover_cache.get(sources)
        except (CoverUnavailable, ImportError, OSError):
            raise HTTPException(503, "Book cover temporarily unavailable",
                                headers={"Retry-After": "60", "Cache-Control": "no-store"}) from None
        media_type = "image/png" if path.suffix == ".png" else "image/webp"
        return FileResponse(path, media_type=media_type, headers={"Cache-Control": "public, max-age=3600"})

    @app.get("/api/v1/classes")
    def classes():
        with db.connect() as tx:
            return tx.all("SELECT * FROM class_levels ORDER BY id")

    @app.get("/api/v1/subjects")
    def subjects():
        with db.connect() as tx:
            return tx.all("SELECT * FROM subjects ORDER BY name_en")

    @app.get("/api/v1/years")
    def years():
        with db.connect() as tx:
            return [row["academic_year"] for row in tx.all(
                "SELECT DISTINCT b.academic_year FROM books b WHERE " + PUBLIC + " ORDER BY b.academic_year DESC")]

    @app.post("/api/v1/reports", status_code=201)
    def report(request: Request, data: Report):
        throttle(request, "report", 6, 3600)
        with db.connect() as tx:
            if not tx.one("SELECT b.id FROM books b WHERE " + PUBLIC + " AND b.id=?", (data.textbook_id,)):
                raise HTTPException(404, "Textbook not found")
            report_id = str(uuid4())
            tx.run("INSERT INTO reports(id,textbook_id,issue_type,description,created_at) VALUES (?,?,?,?,?)",
                   (report_id, data.textbook_id, data.issue_type, data.description, now()))
        return {"id": report_id}

    @app.post("/api/v1/auth/register", status_code=201)
    def register(request: Request, credentials: Credentials):
        throttle(request, "register", 5, 3600)
        if len(credentials.password) < 12:
            raise HTTPException(422, "Use a password with at least 12 characters")
        if os.getenv("BOIPATH_TEACHER_REGISTRATION", "false").lower() != "true":
            raise HTTPException(403, "Teacher registration is closed")
        return create_user(db, credentials, "teacher", with_tokens=True)

    @app.post("/api/v1/auth/login")
    def login(request: Request, credentials: Credentials):
        throttle(request, "login", 8, 300)
        with db.connect() as tx:
            user = tx.one("SELECT * FROM users WHERE email=?", (credentials.email,))
            valid = password_matches(credentials.password, user["password_hash"] if user else DUMMY_HASH)
            if not valid or user is None:
                raise HTTPException(401, "Invalid sign-in credentials")
            result = issue_tokens(tx, user["id"])
        return {**result, "role": user["role"]}

    @app.post("/api/v1/auth/refresh")
    def refresh(request: Request, data: Refresh):
        throttle(request, "refresh", 20)
        with db.connect() as tx:
            row = tx.one("""DELETE FROM tokens WHERE token_hash=? AND kind='refresh' AND expires_at>?
                RETURNING user_id,family""", (token_hash(data.refresh_token), int(time.time())))
            if row is None:
                raise HTTPException(401, "Session expired")
            tx.run("DELETE FROM tokens WHERE family=?", (row["family"],))
            return issue_tokens(tx, row["user_id"], row["family"])

    @app.post("/api/v1/auth/logout")
    def logout(user=Depends(require_user)):
        with db.connect() as tx:
            tx.run("DELETE FROM tokens WHERE family=?", (user["family"],))
        return {"status": "signed_out"}

    @app.get("/api/v1/admin/books")
    def admin_books(user=Depends(require_admin), offset: int = Query(0, ge=0)):
        with db.connect() as tx:
            return tx.all(BOOKS + " ORDER BY b.updated_at DESC,b.id LIMIT 100 OFFSET ?", (offset,))

    def write_book(data, user, book_id=None):
        fields = data.model_dump()
        if book_id is not None and "class_end_id" not in data.model_fields_set:
            fields.pop("class_end_id")
        if fields["verification_status"] == "verified":
            raise HTTPException(422, "Use the verification action to publish a PDF")
        try:
            parse_official_url(data.source_url, NCTB_HOSTS)
            for url in (data.pdf_url, data.cover_url):
                if url is not None:
                    parse_official_url(url, pdf_hosts())
        except ValueError as error:
            raise HTTPException(422, str(error)) from error
        timestamp = now()
        try:
            with db.connect() as tx:
                if book_id is None:
                    book_id = str(uuid4())
                    columns = ("id", "created_at", "updated_at", *fields)
                    tx.run(f"INSERT INTO books ({','.join(columns)}) VALUES ({','.join('?' for _ in columns)})",
                           (book_id, timestamp, timestamp, *fields.values()))
                    audit(tx, user, "create", book_id)
                else:
                    updates = ",".join(f"{name}=?" for name in fields)
                    identity = " AND ".join(f"{field}=?" for field in BOOK_IDENTITY)
                    args = [fields[k] for k in BOOK_IDENTITY]
                    if "class_end_id" in fields:
                        identity += " AND COALESCE(class_end_id,0)=?"
                        args.append(fields["class_end_id"] or 0)
                    result = tx.run(
                        f"""UPDATE books SET {updates},file_size=NULL,last_verified_at=NULL,updated_at=?,
                        source_download_links=CASE WHEN {identity} THEN source_download_links ELSE NULL END WHERE id=?""",
                        (*fields.values(), timestamp, *args, book_id),
                    )
                    if not result.rowcount:
                        raise HTTPException(404, "Textbook not found")
                    audit(tx, user, "edit", book_id)
                return tx.one(BOOKS + " WHERE b.id=?", (book_id,))
        except Exception as error:
            if integrity_error(error):
                raise HTTPException(409, "Duplicate textbook or unknown class/subject") from error
            raise

    @app.post("/api/v1/admin/books", status_code=201)
    def create_book(data: BookInput, user=Depends(require_admin)):
        return write_book(data, user)

    @app.patch("/api/v1/admin/books/{book_id}")
    def edit_book(book_id: str, data: BookInput, user=Depends(require_admin)):
        return write_book(data, user, book_id)

    @app.delete("/api/v1/admin/books/{book_id}")
    def archive_book(book_id: str, user=Depends(require_admin)):
        with db.connect() as tx:
            result = tx.run("UPDATE books SET verification_status='archived',updated_at=? WHERE id=?", (now(), book_id))
            if not result.rowcount:
                raise HTTPException(404, "Textbook not found")
            audit(tx, user, "archive", book_id)
        return {"status": "archived"}

    @app.post("/api/v1/admin/books/{book_id}/verify")
    def publish(request: Request, book_id: str, user=Depends(require_admin)):
        throttle(request, "verify", 12)
        with db.connect() as tx:
            row = tx.one("SELECT pdf_url,updated_at FROM books WHERE id=?", (book_id,))
        if row is None:
            raise HTTPException(404, "Textbook not found")
        if not row["pdf_url"]:
            raise HTTPException(422, "Add a reviewed direct PDF link first")
        try:
            size = verifier(row["pdf_url"])
        except (OSError, ValueError, http.client.HTTPException) as error:
            raise HTTPException(422, "PDF could not be verified from the approved source") from error
        timestamp = now()
        with db.connect() as tx:
            change = tx.run("""UPDATE books SET verification_status='verified',file_size=?,last_verified_at=?,updated_at=?
                WHERE id=? AND updated_at=?""", (size, timestamp, timestamp, book_id, row["updated_at"]))
            if not change.rowcount:
                raise HTTPException(409, "This record changed during verification. Retry.")
            audit(tx, user, "verify", book_id)
            return tx.one(BOOKS + " WHERE b.id=?", (book_id,))

    @app.get("/api/v1/admin/stats")
    def admin_stats(user=Depends(require_admin)):
        with db.connect() as tx:
            rows = tx.all("SELECT verification_status, COUNT(*) AS n FROM books GROUP BY verification_status")
        return {row["verification_status"]: row["n"] for row in rows}

    @app.get("/api/v1/admin/audit")
    def admin_audit(user=Depends(require_admin), offset: int = Query(0, ge=0)):
        with db.connect() as tx:
            return tx.all("SELECT * FROM audit ORDER BY at DESC,id LIMIT 100 OFFSET ?", (offset,))

    @app.get("/api/v1/admin/reports")
    def admin_reports(user=Depends(require_admin), offset: int = Query(0, ge=0)):
        with db.connect() as tx:
            return tx.all("SELECT * FROM reports ORDER BY created_at DESC,id LIMIT 100 OFFSET ?", (offset,))

    @app.patch("/api/v1/admin/reports/{report_id}/resolve")
    def resolve(report_id: str, user=Depends(require_admin)):
        with db.connect() as tx:
            result = tx.run("UPDATE reports SET status='resolved' WHERE id=?", (report_id,))
            if not result.rowcount:
                raise HTTPException(404, "Report not found")
        return {"status": "resolved"}

    install_classrooms(app, db, require_user, throttle, limits, origins)
    return app


def create_user(db, credentials, role, with_tokens=False):
    user_id = str(uuid4())
    encoded = password_hash(credentials.password)
    try:
        with db.connect() as tx:
            tx.run("INSERT INTO users VALUES (?,?,?,?,?)",
                   (user_id, credentials.email, encoded, role, int(time.time())))
            return {**issue_tokens(tx, user_id), "role": role} if with_tokens else {"id": user_id, "role": role}
    except Exception as error:
        if integrity_error(error):
            raise HTTPException(409, "Account already exists") from error
        raise


app = create_app(seed_at_startup=True)
