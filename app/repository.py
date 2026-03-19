from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from app.db import connect_db
from app.schemas import NormalizedLedgerEntry


class LedgerRepository:
    def __init__(self, db_path: str | Path):
        self.db_path = Path(db_path)

    def create_entry(
        self,
        *,
        normalized: NormalizedLedgerEntry,
        intent: str,
        source_image_path: str,
        raw_model_response: dict[str, Any],
    ) -> int:
        with connect_db(self.db_path) as connection:
            cursor = connection.execute(
                """
                INSERT INTO ledger_entries (
                    merchant,
                    currency,
                    original_amount,
                    discount_amount,
                    actual_amount,
                    category,
                    occurred_at,
                    intent,
                    source_image_path,
                    raw_model_response,
                    created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    normalized.merchant,
                    normalized.currency,
                    None if normalized.original_amount is None else str(normalized.original_amount),
                    str(normalized.discount_amount),
                    str(normalized.actual_amount),
                    normalized.category,
                    normalized.occurred_at,
                    intent,
                    source_image_path,
                    json.dumps(raw_model_response, ensure_ascii=True),
                    datetime.now(timezone.utc).isoformat(),
                ),
            )
            connection.commit()
            return int(cursor.lastrowid)

    def list_entries(self, limit: int = 20) -> list[dict[str, Any]]:
        with connect_db(self.db_path) as connection:
            rows = connection.execute(
                """
                SELECT * FROM ledger_entries
                ORDER BY id DESC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
        return [self._row_to_dict(row) for row in rows]

    def get_entry(self, entry_id: int) -> dict[str, Any] | None:
        with connect_db(self.db_path) as connection:
            row = connection.execute(
                "SELECT * FROM ledger_entries WHERE id = ?",
                (entry_id,),
            ).fetchone()
        if row is None:
            return None
        return self._row_to_dict(row)

    @staticmethod
    def _row_to_dict(row: Any) -> dict[str, Any]:
        item = dict(row)
        item["raw_model_response"] = json.loads(item["raw_model_response"])
        return item
