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
        connection.execute(SCHEMA)
        connection.commit()
