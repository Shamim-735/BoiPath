ALTER TABLE books ADD COLUMN class_end_id INTEGER REFERENCES class_levels(id)
    CHECK (class_end_id IS NULL OR (class_end_id > class_id AND class_end_id <= 12));
