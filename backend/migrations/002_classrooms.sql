CREATE TABLE classrooms (
    code TEXT PRIMARY KEY,
    teacher_id TEXT NOT NULL REFERENCES users(id),
    textbook_id TEXT NOT NULL REFERENCES books(id),
    current_page INTEGER NOT NULL CHECK(current_page BETWEEN 1 AND 100000),
    revision INTEGER NOT NULL DEFAULT 0,
    expires_at BIGINT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('active','ended'))
);
CREATE INDEX classrooms_teacher ON classrooms(teacher_id,expires_at);
