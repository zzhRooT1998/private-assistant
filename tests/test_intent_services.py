import pytest

from app.schemas import ScreenIntentResult
from app.services.intents import (
    normalize_reference_entry,
    normalize_schedule_entry,
    normalize_todo_entry,
)
from app.services.vision import VisionIntentService


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


@pytest.mark.parametrize(
    ("speech_text", "expected_intent"),
    [
        ("帮我记这笔账", "bookkeeping"),
        ("提醒我今晚 8 点处理这个", "schedule"),
        ("提醒我回这个消息", "todo"),
        ("帮我保存这个链接，稍后看", "reference"),
        ("安排一下明天下午和 Alex 开会", "schedule"),
    ],
)
def test_infer_explicit_speech_intent_parses_command_patterns(speech_text, expected_intent):
    service = VisionIntentService(
        api_key="test-key",
        base_url="https://example.com/v1",
        model="gpt-test",
        client=object(),
    )

    actual = service.infer_explicit_speech_intent(
        speech_text=speech_text,
        speech_confidence=0.92,
    )

    assert actual == expected_intent


@pytest.mark.parametrize(
    "speech_text",
    [
        "今天收到一张收据",
        "明天下午开会",
        "这个链接不错",
    ],
)
def test_infer_explicit_speech_intent_does_not_force_on_non_command_text(speech_text):
    service = VisionIntentService(
        api_key="test-key",
        base_url="https://example.com/v1",
        model="gpt-test",
        client=object(),
    )

    actual = service.infer_explicit_speech_intent(
        speech_text=speech_text,
        speech_confidence=0.92,
    )

    assert actual is None


def test_infer_explicit_speech_intent_requires_minimum_confidence():
    service = VisionIntentService(
        api_key="test-key",
        base_url="https://example.com/v1",
        model="gpt-test",
        client=object(),
    )

    actual = service.infer_explicit_speech_intent(
        speech_text="帮我记这笔账",
        speech_confidence=0.42,
    )

    assert actual is None
