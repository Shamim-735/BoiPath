CREATE TABLE class_levels (id INTEGER PRIMARY KEY CHECK(id BETWEEN 1 AND 12), name_en TEXT NOT NULL, name_bn TEXT NOT NULL);
CREATE TABLE subjects (id TEXT PRIMARY KEY, name_en TEXT NOT NULL, name_bn TEXT NOT NULL);
CREATE TABLE books (
    id TEXT PRIMARY KEY, official_title TEXT NOT NULL, alternative_title TEXT,
    subject_id TEXT NOT NULL REFERENCES subjects(id), class_id INTEGER NOT NULL REFERENCES class_levels(id),
    academic_year INTEGER NOT NULL CHECK(academic_year BETWEEN 2000 AND 2100),
    language_version TEXT NOT NULL CHECK(language_version IN ('bn','en')),
    curriculum_track TEXT NOT NULL, edition TEXT NOT NULL DEFAULT '', cover_url TEXT, pdf_url TEXT,
    file_size BIGINT CHECK(file_size > 0), source_url TEXT NOT NULL,
    verification_status TEXT NOT NULL CHECK(verification_status IN ('draft','pending','verified','unavailable','archived')),
    last_verified_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
    UNIQUE(official_title,class_id,academic_year,language_version,curriculum_track,edition)
);
CREATE INDEX books_catalog ON books (verification_status,academic_year,class_id,language_version);
CREATE TABLE users (id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('admin','teacher')), created_at BIGINT NOT NULL);
CREATE TABLE tokens (token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK(kind IN ('access','refresh')), expires_at BIGINT NOT NULL, family TEXT NOT NULL);
CREATE INDEX tokens_family ON tokens(family);
CREATE TABLE reports (id TEXT PRIMARY KEY, textbook_id TEXT NOT NULL REFERENCES books(id),
    issue_type TEXT NOT NULL, description TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'open', created_at TEXT NOT NULL);
CREATE TABLE audit (id TEXT PRIMARY KEY, actor TEXT NOT NULL REFERENCES users(id),
    action TEXT NOT NULL, book_id TEXT NOT NULL REFERENCES books(id), at TEXT NOT NULL);
