from __future__ import annotations

from pathlib import Path

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app, get_vision_service
from app.schemas import RankedIntentCandidate, ScreenIntentResult
from app.services.vision import StubVisionIntentService, VisionIntentService


def _make_client(tmp_path: Path, parsed: ScreenIntentResult) -> TestClient:
    settings = Settings(
        openai_api_key="test-key",
        openai_base_url="https://example.com/v1",
        openai_model="gpt-test",
        upload_dir=tmp_path / "uploads",
        database_url=tmp_path / "ledger.db",
    )
    app = create_app(settings)

    def override_vision() -> StubVisionIntentService:
        return StubVisionIntentService(parsed)

    app.dependency_overrides[get_vision_service] = override_vision

    return TestClient(app)


def test_upload_image_and_create_bookkeeping_entry(tmp_path):
    parsed = ScreenIntentResult(
        intent="bookkeeping",
        action="create_bookkeeping_entry",
        confidence=0.93,
        summary="Receipt from Sample Cafe.",
        merchant="Sample Cafe",
        currency="CNY",
        original_amount="42.00",
        discount_amount="8.00",
        actual_amount="34.00",
        category_guess="food",
        occurred_at="2026-03-19T12:30:00+08:00",
    )
    client = _make_client(tmp_path, parsed)

    response = client.post(
        "/agent/life/intake",
        files={"image": ("receipt.jpg", b"fake-image", "image/jpeg")},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["intent"] == "bookkeeping"
    assert data["executed_action"] == "create_bookkeeping_entry"
    assert data["ledger_entry"]["merchant"] == "Sample Cafe"
    assert data["ledger_entry"]["actual_amount"] == "34.00"


def test_upload_image_returns_unknown_without_insertion(tmp_path):
    parsed = ScreenIntentResult(
        intent="unknown",
        action="none",
        confidence=0.51,
        summary="No automatable task found.",
        merchant=None,
        currency=None,
        original_amount=None,
        discount_amount=None,
        actual_amount=None,
        category_guess=None,
        occurred_at=None,
    )
    client = _make_client(tmp_path, parsed)

    response = client.post(
        "/agent/life/intake",
        files={"image": ("other.jpg", b"fake-image", "image/jpeg")},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["intent"] == "unknown"
    assert data["message"] == "No supported automation detected."
    assert data["ledger_entry"] is None

    ledger_response = client.get("/api/ledger")
    assert ledger_response.status_code == 200
    assert ledger_response.json() == []


def test_rejects_non_image_upload(tmp_path):
    parsed = ScreenIntentResult(
        intent="unknown",
        action="none",
        confidence=0.1,
        merchant=None,
        currency=None,
        original_amount=None,
        discount_amount=None,
        actual_amount=None,
        category_guess=None,
        occurred_at=None,
    )
    client = _make_client(tmp_path, parsed)

    response = client.post(
        "/agent/life/intake",
        files={"image": ("receipt.txt", b"not-image", "text/plain")},
    )

    assert response.status_code == 400


def test_root_page_loads(tmp_path):
    parsed = ScreenIntentResult(
        intent="unknown",
        action="none",
        confidence=0.1,
        merchant=None,
        currency=None,
        original_amount=None,
        discount_amount=None,
        actual_amount=None,
        category_guess=None,
        occurred_at=None,
    )
    client = _make_client(tmp_path, parsed)

    response = client.get("/")

    assert response.status_code == 200
    assert "Life Agent MVP" in response.text


def test_returns_502_when_provider_fails(tmp_path):
    settings = Settings(
        openai_api_key="test-key",
        openai_base_url="https://example.com/v1",
        openai_model="gpt-test",
        upload_dir=tmp_path / "uploads",
        database_url=tmp_path / "ledger.db",
    )
    app = create_app(settings)

    class FailingVisionService:
        def rank_intents(
            self,
            *,
            image_path: str | Path | None = None,
            content_type: str | None = None,
            text_input: str | None = None,
            page_url: str | None = None,
            source_app: str | None = None,
            source_type: str | None = None,
            top_k: int = 3,
        ) -> list[RankedIntentCandidate]:
            raise RuntimeError("provider down")

        def parse_input(
            self,
            *,
            image_path: str | Path | None = None,
            content_type: str | None = None,
            text_input: str | None = None,
            page_url: str | None = None,
            source_app: str | None = None,
            source_type: str | None = None,
            forced_intent: str | None = None,
        ) -> ScreenIntentResult:
            raise RuntimeError("provider down")

    app.dependency_overrides[get_vision_service] = lambda: FailingVisionService()
    client = TestClient(app)

    response = client.post(
        "/agent/life/intake",
        files={"image": ("receipt.jpg", b"fake-image", "image/jpeg")},
    )

    assert response.status_code == 502
    assert "provider down" in response.json()["detail"]


def test_returns_500_when_api_key_missing(tmp_path):
    settings = Settings(
        openai_api_key="",
        openai_base_url="https://example.com/v1",
        openai_model="gpt-test",
        upload_dir=tmp_path / "uploads",
        database_url=tmp_path / "ledger.db",
    )
    app = create_app(settings)
    client = TestClient(app)

    response = client.post(
        "/agent/life/intake",
        files={"image": ("receipt.jpg", b"fake-image", "image/jpeg")},
    )

    assert response.status_code == 500
    assert response.json()["detail"] == "OPENAI_API_KEY is not configured"


def test_vision_service_uses_supplied_mime_type(tmp_path):
    payload = (
        '{"intent":"unknown","action":"none","confidence":0.2,"summary":"none",'
        '"source_app":null,"source_type":null,"page_url":null,"extracted_text":null,'
        '"merchant":null,"currency":null,'
        '"original_amount":null,"discount_amount":null,"actual_amount":null,'
        '"category_guess":null,"occurred_at":null}'
    )

    class FakeResponses:
        def __init__(self) -> None:
            self.kwargs = None

        def create(self, **kwargs):
            self.kwargs = kwargs
            return type("Response", (), {"output_text": payload})()

    class FakeClient:
        def __init__(self) -> None:
            self.responses = FakeResponses()

    image_path = tmp_path / "receipt.png"
    image_path.write_bytes(b"fake-image")
    client = FakeClient()
    service = VisionIntentService(
        api_key="test-key",
        base_url="https://example.com/v1",
        model="gpt-test",
        client=client,
    )

    result = service.parse_input(image_path=image_path, content_type="image/png")

    assert result.intent == "unknown"
    image_url = client.responses.kwargs["input"][1]["content"][1]["image_url"]
    assert image_url.startswith("data:image/png;base64,")


def test_vision_service_normalizes_null_confidence(tmp_path):
    payload = (
        '{"intent":"unknown","action":"none","confidence":null,"summary":null,'
        '"source_app":null,"source_type":null,"page_url":null,"extracted_text":null,'
        '"merchant":null,"currency":null,'
        '"original_amount":null,"discount_amount":null,"actual_amount":null,'
        '"category_guess":null,"occurred_at":null}'
    )

    class FakeResponses:
        def create(self, **kwargs):
            return type("Response", (), {"output_text": payload})()

    class FakeClient:
        def __init__(self) -> None:
            self.responses = FakeResponses()

    image_path = tmp_path / "receipt.jpeg"
    image_path.write_bytes(b"fake-image")
    service = VisionIntentService(
        api_key="test-key",
        base_url="https://example.com/v1",
        model="gpt-test",
        client=FakeClient(),
    )

    result = service.parse_input(image_path=image_path, content_type="image/jpeg")

    assert result.intent == "unknown"
    assert result.confidence == 0.0


def test_vision_service_coerces_numeric_amounts_to_strings(tmp_path):
    payload = (
        '{"intent":"bookkeeping","action":"create_bookkeeping_entry","confidence":0.98,'
        '"summary":"Payment receipt","source_app":"Alipay","source_type":"screenshot","page_url":null,"extracted_text":null,'
        '"merchant":"MannerCoffee","currency":"CNY",'
        '"original_amount":20.0,"discount_amount":null,"actual_amount":20.0,'
        '"category_guess":"coffee","occurred_at":null}'
    )

    class FakeResponses:
        def create(self, **kwargs):
            return type("Response", (), {"output_text": payload})()

    class FakeClient:
        def __init__(self) -> None:
            self.responses = FakeResponses()

    image_path = tmp_path / "receipt.jpg"
    image_path.write_bytes(b"fake-image")
    service = VisionIntentService(
        api_key="test-key",
        base_url="https://example.com/v1",
        model="gpt-test",
        client=FakeClient(),
    )

    result = service.parse_input(image_path=image_path, content_type="image/jpeg")

    assert result.intent == "bookkeeping"
    assert result.original_amount == "20.0"
    assert result.actual_amount == "20.0"


def test_mobile_intake_accepts_text_url_and_metadata(tmp_path):
    parsed = ScreenIntentResult(
        intent="todo",
        action="create_todo",
        confidence=0.81,
        summary="Remember to reply to this message later.",
        source_app="WeChat",
        source_type="onscreen",
        page_url="https://example.com/chat/123",
        extracted_text="Please send the revised deck tonight.",
        todo_title="Reply to the revised deck message",
        todo_details="Please send the revised deck tonight.",
        todo_due_at="2026-03-23T22:00:00+08:00",
    )
    client = _make_client(tmp_path, parsed)

    response = client.post(
        "/agent/life/mobile-intake",
        data={
            "text_input": "Please send the revised deck tonight.",
            "page_url": "https://example.com/chat/123",
            "source_app": "WeChat",
            "source_type": "onscreen",
            "captured_at": "2026-03-23T20:15:00+08:00",
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert data["intent"] == "todo"
    assert data["analysis"]["source_app"] == "WeChat"
    assert data["executed_action"] == "create_todo"
    assert data["todo_entry"]["title"] == "Reply to the revised deck message"
    assert data["message"] == "Todo entry created."

    todo_response = client.get("/api/todos")
    assert todo_response.status_code == 200
    assert todo_response.json()[0]["title"] == "Reply to the revised deck message"


def test_mobile_intake_requires_payload(tmp_path):
    parsed = ScreenIntentResult(
        intent="unknown",
        action="none",
        confidence=0.2,
    )
    client = _make_client(tmp_path, parsed)

    response = client.post("/agent/life/mobile-intake", data={})

    assert response.status_code == 400
    assert response.json()["detail"] == "Provide at least one of image, text_input, or page_url"


def test_vision_service_includes_text_and_url_context(tmp_path):
    payload = (
        '{"intent":"reference","action":"save_reference","confidence":0.76,"summary":"Save this article for later.",'
        '"source_app":"Safari","source_type":"onscreen","page_url":"https://example.com/article","extracted_text":"Interesting article",'
        '"merchant":null,"currency":null,"original_amount":null,"discount_amount":null,"actual_amount":null,'
        '"todo_title":null,"todo_details":null,"todo_due_at":null,'
        '"reference_title":"Interesting article","reference_summary":"Save this article for later.",'
        '"schedule_title":null,"schedule_details":null,"schedule_start_at":null,"schedule_end_at":null,'
        '"category_guess":null,"occurred_at":null}'
    )

    class FakeResponses:
        def __init__(self) -> None:
            self.kwargs = None

        def create(self, **kwargs):
            self.kwargs = kwargs
            return type("Response", (), {"output_text": payload})()

    class FakeClient:
        def __init__(self) -> None:
            self.responses = FakeResponses()

    service = VisionIntentService(
        api_key="test-key",
        base_url="https://example.com/v1",
        model="gpt-test",
        client=FakeClient(),
    )

    result = service.parse_input(
        text_input="Interesting article",
        page_url="https://example.com/article",
        source_app="Safari",
        source_type="onscreen",
    )

    assert result.intent == "reference"
    prompt_text = service.client.responses.kwargs["input"][1]["content"][0]["text"]
    assert "Source app: Safari" in prompt_text
    assert "Page URL: https://example.com/article" in prompt_text
    assert "Shared text:\nInteresting article" in prompt_text


def test_vision_service_extracts_dict_style_response_text(tmp_path):
    payload = (
        '{"intent":"unknown","action":"none","confidence":0.3,"summary":"No action.",'
        '"source_app":null,"source_type":"screenshot","page_url":null,"extracted_text":null,'
        '"merchant":null,"currency":null,"original_amount":null,"discount_amount":null,"actual_amount":null,'
        '"todo_title":null,"todo_details":null,"todo_due_at":null,'
        '"reference_title":null,"reference_summary":null,'
        '"schedule_title":null,"schedule_details":null,"schedule_start_at":null,"schedule_end_at":null,'
        '"category_guess":null,"occurred_at":null}'
    )

    class FakeResponses:
        def create(self, **kwargs):
            return {
                "output": [
                    {
                        "content": [
                            {
                                "type": "output_text",
                                "text": payload,
                            }
                        ]
                    }
                ]
            }

    class FakeClient:
        def __init__(self) -> None:
            self.responses = FakeResponses()

    image_path = tmp_path / "capture.jpg"
    image_path.write_bytes(b"fake-image")
    service = VisionIntentService(
        api_key="test-key",
        base_url="https://example.com/v1",
        model="gpt-test",
        client=FakeClient(),
    )

    result = service.parse_input(image_path=image_path, content_type="image/jpeg")

    assert result.intent == "unknown"
    assert result.source_type == "screenshot"


def test_vision_service_extracts_list_output_text(tmp_path):
    payload = (
        '{"intent":"reference","action":"save_reference","confidence":0.7,"summary":"Save item.",'
        '"source_app":"Photos","source_type":"screenshot","page_url":null,"extracted_text":null,'
        '"merchant":null,"currency":null,"original_amount":null,"discount_amount":null,"actual_amount":null,'
        '"todo_title":null,"todo_details":null,"todo_due_at":null,'
        '"reference_title":"Saved item","reference_summary":"Save item.",'
        '"schedule_title":null,"schedule_details":null,"schedule_start_at":null,"schedule_end_at":null,'
        '"category_guess":null,"occurred_at":null}'
    )

    class FakeResponses:
        def create(self, **kwargs):
            return type(
                "Response",
                (),
                {"output_text": [{"text": payload}]},
            )()

    class FakeClient:
        def __init__(self) -> None:
            self.responses = FakeResponses()

    image_path = tmp_path / "capture.jpg"
    image_path.write_bytes(b"fake-image")
    service = VisionIntentService(
        api_key="test-key",
        base_url="https://example.com/v1",
        model="gpt-test",
        client=FakeClient(),
    )

    result = service.parse_input(image_path=image_path, content_type="image/jpeg")

    assert result.intent == "reference"
    assert result.reference_title == "Saved item"


def test_vision_service_uses_chat_completions_for_dashscope(tmp_path):
    payload = (
        '{"intent":"bookkeeping","action":"create_bookkeeping_entry","confidence":0.91,"summary":"Receipt saved.",'
        '"source_app":null,"source_type":"screenshot","page_url":null,"extracted_text":null,'
        '"merchant":"Manner","currency":"CNY","original_amount":"20.0","discount_amount":null,"actual_amount":"20.0",'
        '"todo_title":null,"todo_details":null,"todo_due_at":null,'
        '"reference_title":null,"reference_summary":null,'
        '"schedule_title":null,"schedule_details":null,"schedule_start_at":null,"schedule_end_at":null,'
        '"category_guess":"coffee","occurred_at":null}'
    )

    class FakeChatCompletions:
        def __init__(self) -> None:
            self.kwargs = None

        def create(self, **kwargs):
            self.kwargs = kwargs
            return {
                "choices": [
                    {
                        "message": {
                            "content": payload,
                        }
                    }
                ]
            }

    class FakeClient:
        def __init__(self) -> None:
            self.chat = type("Chat", (), {"completions": FakeChatCompletions()})()
            self.responses = None

    image_path = tmp_path / "receipt.png"
    image_path.write_bytes(b"fake-image")
    client = FakeClient()
    service = VisionIntentService(
        api_key="test-key",
        base_url="https://dashscope.aliyuncs.com/compatible-mode/v1",
        model="qwen3-vl-plus",
        client=client,
    )

    result = service.parse_input(image_path=image_path, content_type="image/png")

    assert result.intent == "bookkeeping"
    assert client.chat.completions.kwargs["model"] == "qwen3-vl-plus"
    content = client.chat.completions.kwargs["messages"][1]["content"]
    assert content[0]["type"] == "text"
    assert content[1]["type"] == "image_url"


def test_mobile_intake_creates_reference_entry(tmp_path):
    parsed = ScreenIntentResult(
        intent="reference",
        action="save_reference",
        confidence=0.72,
        summary="Save this article for later.",
        source_app="Safari",
        source_type="onscreen",
        page_url="https://example.com/article",
        extracted_text="Interesting article",
        reference_title="Interesting article",
        reference_summary="Save this article for later.",
    )
    client = _make_client(tmp_path, parsed)

    response = client.post(
        "/agent/life/mobile-intake",
        data={
            "text_input": "Interesting article",
            "page_url": "https://example.com/article",
            "source_app": "Safari",
            "source_type": "onscreen",
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert data["executed_action"] == "save_reference"
    assert data["reference_entry"]["title"] == "Interesting article"

    references_response = client.get("/api/references")
    assert references_response.status_code == 200
    assert references_response.json()[0]["page_url"] == "https://example.com/article"


def test_mobile_intake_creates_schedule_entry(tmp_path):
    parsed = ScreenIntentResult(
        intent="schedule",
        action="schedule_event",
        confidence=0.88,
        summary="Dentist appointment tomorrow afternoon.",
        source_app="Messages",
        source_type="share_extension",
        extracted_text="Dentist at 3pm tomorrow",
        schedule_title="Dentist appointment",
        schedule_details="Dentist at 3pm tomorrow",
        schedule_start_at="2026-03-24T15:00:00+08:00",
        schedule_end_at="2026-03-24T16:00:00+08:00",
    )
    client = _make_client(tmp_path, parsed)

    response = client.post(
        "/agent/life/mobile-intake",
        data={
            "text_input": "Dentist at 3pm tomorrow",
            "source_app": "Messages",
            "source_type": "share_extension",
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert data["executed_action"] == "schedule_event"
    assert data["schedule_entry"]["title"] == "Dentist appointment"

    schedules_response = client.get("/api/schedules")
    assert schedules_response.status_code == 200
    assert schedules_response.json()[0]["start_at"] == "2026-03-24T15:00:00+08:00"


def test_mobile_intake_returns_200_when_intent_cannot_be_normalized(tmp_path):
    parsed = ScreenIntentResult(
        intent="schedule",
        action="schedule_event",
        confidence=0.64,
        summary="Maybe this is a meeting.",
        source_type="screenshot",
        schedule_title="Possible meeting",
        schedule_start_at=None,
    )
    client = _make_client(tmp_path, parsed)

    response = client.post(
        "/agent/life/mobile-intake",
        files={"image": ("capture.png", b"fake-image", "image/png")},
        data={"source_type": "screenshot"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["intent"] == "schedule"
    assert data["executed_action"] is None
    assert data["schedule_entry"] is None
    assert data["message"] == "Intent detected but not executed yet: schedule."


def test_mobile_intake_returns_ranked_intents_for_hitl_confirmation(tmp_path):
    parsed = ScreenIntentResult(
        intent="todo",
        action="create_todo",
        confidence=0.58,
        summary="Follow up on this item.",
        todo_title="Follow up",
    )
    ranked_intents = [
        RankedIntentCandidate(intent="todo", confidence=0.58, reason="Looks actionable."),
        RankedIntentCandidate(intent="reference", confidence=0.51, reason="Could also be saved."),
        RankedIntentCandidate(intent="schedule", confidence=0.44, reason="Could imply a reminder."),
    ]
    settings = Settings(
        openai_api_key="test-key",
        openai_base_url="https://example.com/v1",
        openai_model="gpt-test",
        upload_dir=tmp_path / "uploads",
        database_url=tmp_path / "ledger.db",
    )
    app = create_app(settings)
    app.dependency_overrides[get_vision_service] = lambda: StubVisionIntentService(parsed, ranked_intents=ranked_intents)
    client = TestClient(app)

    response = client.post(
        "/agent/life/mobile-intake",
        files={"image": ("capture.jpg", b"fake-image", "image/jpeg")},
        data={"source_type": "screenshot"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["requires_confirmation"] is True
    assert data["review_id"] is not None
    assert len(data["ranked_intents"]) == 3
    assert data["executed_action"] is None

    pending_reviews_response = client.get("/api/intent-reviews")
    assert pending_reviews_response.status_code == 200
    pending_reviews = pending_reviews_response.json()
    assert len(pending_reviews) == 1
    assert pending_reviews[0]["id"] == data["review_id"]
    assert pending_reviews[0]["status"] == "pending"
    assert pending_reviews[0]["confirmation_reason"] is not None
    assert pending_reviews[0]["ranked_intents"][0]["intent"] == "todo"


def test_confirm_mobile_intake_executes_selected_intent(tmp_path):
    parsed = ScreenIntentResult(
        intent="todo",
        action="create_todo",
        confidence=0.58,
        summary="Follow up on this item.",
        todo_title="Follow up",
    )
    ranked_intents = [
        RankedIntentCandidate(intent="todo", confidence=0.58, reason="Looks actionable."),
        RankedIntentCandidate(intent="reference", confidence=0.51, reason="Could also be saved."),
        RankedIntentCandidate(intent="schedule", confidence=0.44, reason="Could imply a reminder."),
    ]
    settings = Settings(
        openai_api_key="test-key",
        openai_base_url="https://example.com/v1",
        openai_model="gpt-test",
        upload_dir=tmp_path / "uploads",
        database_url=tmp_path / "ledger.db",
    )
    app = create_app(settings)
    app.dependency_overrides[get_vision_service] = lambda: StubVisionIntentService(parsed, ranked_intents=ranked_intents)
    client = TestClient(app)

    intake_response = client.post(
        "/agent/life/mobile-intake",
        files={"image": ("capture.jpg", b"fake-image", "image/jpeg")},
        data={"source_type": "screenshot"},
    )
    review_id = intake_response.json()["review_id"]

    confirm_response = client.post(
        f"/agent/life/mobile-intake/{review_id}/confirm",
        json={"selected_intent": "todo"},
    )

    assert confirm_response.status_code == 200
    data = confirm_response.json()
    assert data["requires_confirmation"] is False
    assert data["executed_action"] == "create_todo"
    assert data["todo_entry"]["title"] == "Follow up"

    pending_reviews_response = client.get("/api/intent-reviews")
    assert pending_reviews_response.status_code == 200
    assert pending_reviews_response.json() == []
