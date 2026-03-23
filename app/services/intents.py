from __future__ import annotations

from app.schemas import (
    NormalizedReferenceEntry,
    NormalizedScheduleEntry,
    NormalizedTodoEntry,
    ScreenIntentResult,
)


def normalize_todo_entry(parsed: ScreenIntentResult) -> NormalizedTodoEntry:
    title = _first_non_empty(parsed.todo_title, parsed.summary, parsed.extracted_text)
    if title is None:
        raise ValueError("Missing todo title")

    return NormalizedTodoEntry(
        title=_truncate(title, 160),
        details=_first_non_empty(parsed.todo_details, parsed.extracted_text),
        due_at=parsed.todo_due_at,
        source_app=parsed.source_app,
        page_url=parsed.page_url,
    )


def normalize_reference_entry(parsed: ScreenIntentResult) -> NormalizedReferenceEntry:
    title = _first_non_empty(parsed.reference_title, parsed.summary, parsed.page_url, parsed.extracted_text)
    if title is None:
        raise ValueError("Missing reference title")

    return NormalizedReferenceEntry(
        title=_truncate(title, 200),
        summary=_first_non_empty(parsed.reference_summary, parsed.summary, parsed.extracted_text),
        page_url=parsed.page_url,
        source_app=parsed.source_app,
    )


def normalize_schedule_entry(parsed: ScreenIntentResult) -> NormalizedScheduleEntry:
    title = _first_non_empty(parsed.schedule_title, parsed.summary, parsed.extracted_text)
    if title is None:
        raise ValueError("Missing schedule title")
    if not _has_text(parsed.schedule_start_at):
        raise ValueError("Missing schedule start time")

    return NormalizedScheduleEntry(
        title=_truncate(title, 160),
        details=_first_non_empty(parsed.schedule_details, parsed.extracted_text),
        start_at=parsed.schedule_start_at or "",
        end_at=parsed.schedule_end_at,
        source_app=parsed.source_app,
        page_url=parsed.page_url,
    )


def _first_non_empty(*values: str | None) -> str | None:
    for value in values:
        if _has_text(value):
            return value.strip()
    return None


def _has_text(value: str | None) -> bool:
    return value is not None and bool(value.strip())


def _truncate(value: str, limit: int) -> str:
    if len(value) <= limit:
        return value
    return value[: limit - 1].rstrip() + "…"
