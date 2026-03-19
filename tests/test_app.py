from __future__ import annotations

from pathlib import Path

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app, get_vision_service
from app.schemas import ReceiptParseResult
from app.services.vision import StubVisionIntentService, VisionIntentService


def _make_client(tmp_path: Path, parsed: ReceiptParseResult) -> TestClient:
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
    parsed = ReceiptParseResult(
        intent="bookkeeping",
        confidence=0.93,
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
    assert data["ledger_entry"]["merchant"] == "Sample Cafe"
    assert data["ledger_entry"]["actual_amount"] == "34.00"


def test_upload_image_returns_unknown_without_insertion(tmp_path):
    parsed = ReceiptParseResult(
        intent="unknown",
        confidence=0.51,
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
    assert data["ledger_entry"] is None

    ledger_response = client.get("/api/ledger")
    assert ledger_response.status_code == 200
    assert ledger_response.json() == []


def test_rejects_non_image_upload(tmp_path):
    parsed = ReceiptParseResult(
        intent="unknown",
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
    parsed = ReceiptParseResult(
        intent="unknown",
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
        def parse_receipt(self, image_path: str | Path, content_type: str | None = None) -> ReceiptParseResult:
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
        '{"intent":"unknown","confidence":0.2,"merchant":null,"currency":null,'
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

    result = service.parse_receipt(image_path, content_type="image/png")

    assert result.intent == "unknown"
    image_url = client.responses.kwargs["input"][1]["content"][1]["image_url"]
    assert image_url.startswith("data:image/png;base64,")


def test_vision_service_normalizes_null_confidence(tmp_path):
    payload = (
        '{"intent":"unknown","confidence":null,"merchant":null,"currency":null,'
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

    result = service.parse_receipt(image_path, content_type="image/jpeg")

    assert result.intent == "unknown"
    assert result.confidence == 0.0


def test_vision_service_coerces_numeric_amounts_to_strings(tmp_path):
    payload = (
        '{"intent":"bookkeeping","confidence":0.98,"merchant":"MannerCoffee","currency":"CNY",'
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

    result = service.parse_receipt(image_path, content_type="image/jpeg")

    assert result.intent == "bookkeeping"
    assert result.original_amount == "20.0"
    assert result.actual_amount == "20.0"
