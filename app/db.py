from __future__ import annotations

import sqlite3
from pathlib import Path


SCHEMA = """
CREATE TABLE IF NOT EXISTS ledger_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  merchant TEXT,
  currency TEXT,
  original_amount TEXT,
  discount_amount TEXT NOT NULL,
  actual_amount TEXT NOT NULL,
  category TEXT,
  occurred_at TEXT,
  intent TEXT NOT NULL,
  source_image_path TEXT NOT NULL,
  raw_model_response TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS todo_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  details TEXT,
  due_at TEXT,
  source_app TEXT,
  page_url TEXT,
  raw_model_response TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS reference_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  summary TEXT,
  page_url TEXT,
  source_app TEXT,
  raw_model_response TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS schedule_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  details TEXT,
  start_at TEXT NOT NULL,
  end_at TEXT,
  source_app TEXT,
  page_url TEXT,
  raw_model_response TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS intent_reviews (
  id TEXT PRIMARY KEY,
  image_path TEXT,
  content_type TEXT,
  text_input TEXT,
  page_url TEXT,
  source_app TEXT,
  source_type TEXT,
  captured_at TEXT,
  ranked_intents TEXT NOT NULL,
  status TEXT NOT NULL,
  selected_intent TEXT,
  confirmation_reason TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
"""


def connect_db(db_path: str | Path) -> sqlite3.Connection:
    connection = sqlite3.connect(db_path)
    connection.row_factory = sqlite3.Row
    return connection


def init_db(db_path: str | Path) -> None:
    path = Path(db_path)
    if path.parent != Path("."):
        path.parent.mkdir(parents=True, exist_ok=True)
    with connect_db(path) as connection:
        connection.executescript(SCHEMA)
        _ensure_intent_review_columns(connection)
        connection.commit()


def _ensure_intent_review_columns(connection: sqlite3.Connection) -> None:
    existing_columns = {
        row["name"] for row in connection.execute("PRAGMA table_info(intent_reviews)").fetchall()
    }
    if "confirmation_reason" not in existing_columns:
        connection.execute("ALTER TABLE intent_reviews ADD COLUMN confirmation_reason TEXT")
