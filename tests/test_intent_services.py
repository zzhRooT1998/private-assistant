import pytest

from app.schemas import ScreenIntentResult
from app.services.intents import (
    normalize_reference_entry,
    normalize_schedule_entry,
    normalize_todo_entry,
)


def test_normalize_todo_entry_prefers_explicit_title():
    parsed = ScreenIntentResult(
        intent="todo",
        confidence=0.8,
        summary="Reply to the team tonight.",
        extracted_text="Reply to the team tonight.",
        todo_title="Reply to team",
        todo_details="Send the revised deck tonight.",
        todo_due_at="2026-03-23T22:00:00+08:00",
        source_app="WeChat",
        page_url="https://example.com/chat/123",
    )

    entry = normalize_todo_entry(parsed)

    assert entry.title == "Reply to team"
    assert entry.due_at == "2026-03-23T22:00:00+08:00"


def test_normalize_reference_entry_requires_title():
    parsed = ScreenIntentResult(
        intent="reference",
        confidence=0.7,
    )

    with pytest.raises(ValueError):
        normalize_reference_entry(parsed)


def test_normalize_schedule_entry_requires_start_time():
    parsed = ScreenIntentResult(
        intent="schedule",
        confidence=0.85,
        schedule_title="Dentist appointment",
    )

    with pytest.raises(ValueError):
        normalize_schedule_entry(parsed)
