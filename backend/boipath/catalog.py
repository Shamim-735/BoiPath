"""Install the bundled public catalog without overwriting existing book records."""
import json
import re
from pathlib import Path

from .db import now
from .schemas import BookInput

SOURCE_DOWNLOAD = re.compile(
    r"https://(?:drive\.egovcloud\.gov\.bd/(?:index\.php/)?s/[A-Za-z0-9]+/download"
    r"|drive\.google\.com/uc\?export=download&id=[A-Za-z0-9_-]+)"
)
BOOK_IDENTITY = ("official_title", "subject_id", "class_id", "academic_year", "language_version",
                 "curriculum_track", "edition", "source_url")
SEED_FILE = Path(__file__).resolve().parents[1] / "seed.json"


def seed_catalog(db):
    rows = json.loads(SEED_FILE.read_text(encoding="utf-8"))
    timestamp = now()
    with db.connect() as tx:
        for row in rows:
            book = dict(row)
            book_id = book.pop("id")
            english = book.pop("subject_en")
            bangla = book.pop("subject_bn")
            urls = book.pop("source_download_urls")
            if not urls or any(not SOURCE_DOWNLOAD.fullmatch(url) for url in urls):
                raise ValueError(f"Invalid bundled textbook download for {book_id}")
            links = json.dumps(urls)
            fields = BookInput.model_validate(book).model_dump()
            tx.run("INSERT INTO subjects (id,name_en,name_bn) VALUES (?,?,?) ON CONFLICT DO NOTHING",
                   (fields["subject_id"], english, bangla))
            columns = ("id", *fields, "created_at", "updated_at", "source_download_links")
            tx.run(f"INSERT INTO books ({','.join(columns)}) VALUES ({','.join('?' for _ in columns)}) "
                   "ON CONFLICT DO NOTHING", (book_id, *fields.values(), timestamp, timestamp, links))
            match = " AND ".join(f"{field}=?" for field in BOOK_IDENTITY)
            grade = fields["class_end_id"] or 0
            tx.run(f"""UPDATE books SET source_download_links=?
                WHERE id=? AND source_download_links IS NULL AND {match} AND COALESCE(class_end_id,0)=?""",
                (links, book_id, *(fields[k] for k in BOOK_IDENTITY), grade))
    return len(rows)
