from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4

from app.db import connect_db
from app.schemas import (
    NormalizedLedgerEntry,
    NormalizedReferenceEntry,
    NormalizedScheduleEntry,
    NormalizedTodoEntry,
    RankedIntentCandidate,
)


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

    def create_todo_entry(
        self,
        *,
        normalized: NormalizedTodoEntry,
        raw_model_response: dict[str, Any],
    ) -> int:
        with connect_db(self.db_path) as connection:
            cursor = connection.execute(
                """
                INSERT INTO todo_entries (
                    title,
                    details,
                    due_at,
                    source_app,
                    page_url,
                    raw_model_response,
                    created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    normalized.title,
                    normalized.details,
                    normalized.due_at,
                    normalized.source_app,
                    normalized.page_url,
                    json.dumps(raw_model_response, ensure_ascii=True),
                    datetime.now(timezone.utc).isoformat(),
                ),
            )
            connection.commit()
            return int(cursor.lastrowid)

    def list_todo_entries(self, limit: int = 20) -> list[dict[str, Any]]:
        return self._list_rows("todo_entries", limit=limit)

    def get_todo_entry(self, entry_id: int) -> dict[str, Any] | None:
        return self._get_row("todo_entries", entry_id)

    def create_reference_entry(
        self,
        *,
        normalized: NormalizedReferenceEntry,
        raw_model_response: dict[str, Any],
    ) -> int:
        with connect_db(self.db_path) as connection:
            cursor = connection.execute(
                """
                INSERT INTO reference_entries (
                    title,
                    summary,
                    page_url,
                    source_app,
                    raw_model_response,
                    created_at
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    normalized.title,
                    normalized.summary,
                    normalized.page_url,
                    normalized.source_app,
                    json.dumps(raw_model_response, ensure_ascii=True),
                    datetime.now(timezone.utc).isoformat(),
                ),
            )
            connection.commit()
            return int(cursor.lastrowid)

    def list_reference_entries(self, limit: int = 20) -> list[dict[str, Any]]:
        return self._list_rows("reference_entries", limit=limit)

    def get_reference_entry(self, entry_id: int) -> dict[str, Any] | None:
        return self._get_row("reference_entries", entry_id)

    def create_schedule_entry(
        self,
        *,
        normalized: NormalizedScheduleEntry,
        raw_model_response: dict[str, Any],
    ) -> int:
        with connect_db(self.db_path) as connection:
            cursor = connection.execute(
                """
                INSERT INTO schedule_entries (
                    title,
                    details,
                    start_at,
                    end_at,
                    source_app,
                    page_url,
                    raw_model_response,
                    created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    normalized.title,
                    normalized.details,
                    normalized.start_at,
                    normalized.end_at,
                    normalized.source_app,
                    normalized.page_url,
                    json.dumps(raw_model_response, ensure_ascii=True),
                    datetime.now(timezone.utc).isoformat(),
                ),
            )
            connection.commit()
            return int(cursor.lastrowid)

    def list_schedule_entries(self, limit: int = 20) -> list[dict[str, Any]]:
        return self._list_rows("schedule_entries", limit=limit)

    def get_schedule_entry(self, entry_id: int) -> dict[str, Any] | None:
        return self._get_row("schedule_entries", entry_id)

    def create_intent_review(
        self,
        *,
        image_path: str | None,
        content_type: str | None,
        text_input: str | None,
        page_url: str | None,
        source_app: str | None,
        source_type: str | None,
        captured_at: str | None,
        ranked_intents: list[RankedIntentCandidate],
        confirmation_reason: str | None,
    ) -> str:
        review_id = uuid4().hex
        now = datetime.now(timezone.utc).isoformat()
        with connect_db(self.db_path) as connection:
            connection.execute(
                """
                INSERT INTO intent_reviews (
                    id,
                    image_path,
                    content_type,
                    text_input,
                    page_url,
                    source_app,
                    source_type,
                    captured_at,
                    ranked_intents,
                    status,
                    selected_intent,
                    confirmation_reason,
                    created_at,
                    updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    review_id,
                    image_path,
                    content_type,
                    text_input,
                    page_url,
                    source_app,
                    source_type,
                    captured_at,
                    json.dumps([candidate.model_dump() for candidate in ranked_intents], ensure_ascii=True),
                    "pending",
                    None,
                    confirmation_reason,
                    now,
                    now,
                ),
            )
            connection.commit()
        return review_id

    def get_intent_review(self, review_id: str) -> dict[str, Any] | None:
        return self._get_row("intent_reviews", review_id, key_column="id")

    def list_intent_reviews(self, *, status: str | None = None, limit: int = 20) -> list[dict[str, Any]]:
        with connect_db(self.db_path) as connection:
            if status is None:
                rows = connection.execute(
                    """
                    SELECT * FROM intent_reviews
                    ORDER BY created_at DESC
                    LIMIT ?
                    """,
                    (limit,),
                ).fetchall()
            else:
                rows = connection.execute(
                    """
                    SELECT * FROM intent_reviews
                    WHERE status = ?
                    ORDER BY created_at DESC
                    LIMIT ?
                    """,
                    (status, limit),
                ).fetchall()
        return [self._row_to_dict(row) for row in rows]

    def complete_intent_review(self, review_id: str, *, selected_intent: str) -> None:
        with connect_db(self.db_path) as connection:
            connection.execute(
                """
                UPDATE intent_reviews
                SET status = ?, selected_intent = ?, updated_at = ?
                WHERE id = ?
                """,
                ("completed", selected_intent, datetime.now(timezone.utc).isoformat(), review_id),
            )
            connection.commit()

    def _list_rows(self, table_name: str, *, limit: int) -> list[dict[str, Any]]:
        with connect_db(self.db_path) as connection:
            rows = connection.execute(
                f"""
                SELECT * FROM {table_name}
                ORDER BY id DESC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
        return [self._row_to_dict(row) for row in rows]

    def _get_row(self, table_name: str, entry_id: int | str, *, key_column: str = "id") -> dict[str, Any] | None:
        with connect_db(self.db_path) as connection:
            row = connection.execute(
                f"SELECT * FROM {table_name} WHERE {key_column} = ?",
                (entry_id,),
            ).fetchone()
        if row is None:
            return None
        return self._row_to_dict(row)

    @staticmethod
    def _row_to_dict(row: Any) -> dict[str, Any]:
        item = dict(row)
        raw_model_response = item.get("raw_model_response")
        if raw_model_response is not None:
            item["raw_model_response"] = json.loads(raw_model_response)
        ranked_intents = item.get("ranked_intents")
        if ranked_intents is not None:
            item["ranked_intents"] = json.loads(ranked_intents)
        return item
