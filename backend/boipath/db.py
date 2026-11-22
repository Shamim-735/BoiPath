import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

MIGRATIONS = Path(__file__).resolve().parents[1] / "migrations"


def now():
    return datetime.now(timezone.utc).isoformat()


class Database:
    def __init__(self, url):
        self.url = url
        self.postgres = url.startswith(("postgres://", "postgresql://"))

    @contextmanager
    def connect(self):
        if self.postgres:
            import psycopg
            from psycopg.rows import dict_row

            connection = psycopg.connect(self.url, row_factory=dict_row)
        else:
            connection = sqlite3.connect(self.url, timeout=10)
            connection.row_factory = sqlite3.Row
            connection.execute("PRAGMA foreign_keys = ON")
        try:
            yield Transaction(connection, self.postgres)
            connection.commit()
        except BaseException:
            connection.rollback()
            raise
        finally:
            connection.close()

    def migrate(self):
        with self.connect() as tx:
            if self.postgres:
                tx.run("SELECT pg_advisory_xact_lock(862714)")
            else:
                tx.run("BEGIN IMMEDIATE")
            tx.run("CREATE TABLE IF NOT EXISTS migrations (name TEXT PRIMARY KEY)")
            applied = {row["name"] for row in tx.all("SELECT name FROM migrations")}
            for path in sorted(MIGRATIONS.glob("*.sql")):
                if path.name in applied:
                    continue
                for statement in path.read_text().split(";"):
                    if statement.strip():
                        tx.run(statement)
                tx.run("INSERT INTO migrations(name) VALUES (?)", (path.name,))
            for level in range(1, 13):
                bn = str(level).translate(str.maketrans("0123456789", "০১২৩৪৫৬৭৮৯"))
                tx.run("INSERT INTO class_levels VALUES (?,?,?) ON CONFLICT DO NOTHING",
                       (level, f"Class {level}", f"শ্রেণি {bn}"))
            for subject in (("bangla", "Bangla", "বাংলা"), ("english", "English", "ইংরেজি"),
                            ("mathematics", "Mathematics", "গণিত"), ("science", "Science", "বিজ্ঞান"),
                            ("social-studies", "Social Studies", "সমাজবিজ্ঞান"), ("other", "Other", "অন্যান্য")):
                tx.run("INSERT INTO subjects VALUES (?,?,?) ON CONFLICT DO NOTHING", subject)


class Transaction:
    def __init__(self, connection, postgres):
        self.connection = connection
        self.postgres = postgres

    def run(self, sql, args=()):
        return self.connection.execute(sql.replace("?", "%s") if self.postgres else sql, args)

    def one(self, sql, args=()):
        row = self.run(sql, args).fetchone()
        return dict(row) if row is not None else None

    def all(self, sql, args=()):
        return [dict(row) for row in self.run(sql, args).fetchall()]


def default_database():
    return Database(os.environ.get("DATABASE_URL", "boipath.sqlite3"))


def integrity_error(error):
    return isinstance(error, sqlite3.IntegrityError) or any(
        cls.__name__ == "IntegrityError" for cls in type(error).__mro__
    )
