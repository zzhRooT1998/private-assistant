from __future__ import annotations

import logging
import shutil
from pathlib import Path
from uuid import uuid4

from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from app.config import Settings, get_settings
from app.db import init_db
from app.repository import LedgerRepository
from app.schemas import (
    ConfirmIntentRequest,
    IntakeResponse,
    IntentReview,
    RankedIntentCandidate,
    SUPPORTED_INTENTS,
    ScreenIntentResult,
)
from app.services.bookkeeping import normalize_bookkeeping_entry
from app.services.intent_graph import IntentWorkflowService
from app.services.intents import (
    normalize_reference_entry,
    normalize_schedule_entry,
    normalize_todo_entry,
)
from app.services.vision import VisionIntentService

logger = logging.getLogger(__name__)


def get_repository(request: Request) -> LedgerRepository:
    return LedgerRepository(request.app.state.settings.database_url)


def get_vision_service(request: Request) -> VisionIntentService:
    settings_obj = request.app.state.settings
    if not settings_obj.openai_api_key:
        raise HTTPException(status_code=500, detail="OPENAI_API_KEY is not configured")
    if not settings_obj.openai_base_url:
        raise HTTPException(status_code=500, detail="OPENAI_BASE_URL is not configured")
    if not settings_obj.openai_model:
        raise HTTPException(status_code=500, detail="OPENAI_MODEL is not configured")
    return VisionIntentService(
        api_key=settings_obj.openai_api_key,
        base_url=settings_obj.openai_base_url,
        model=settings_obj.openai_model,
    )


def get_intent_workflow_service(
    vision: VisionIntentService = Depends(get_vision_service),
) -> IntentWorkflowService:
    return IntentWorkflowService(vision)


def create_app(settings: Settings | None = None) -> FastAPI:
    app = FastAPI(title="Private Assistant")
    app.state.settings = settings or get_settings()
    app.state.settings.upload_dir.mkdir(parents=True, exist_ok=True)
    init_db(app.state.settings.database_url)
    templates = Jinja2Templates(directory=str(Path(__file__).parent / "templates"))

    @app.get("/", response_class=HTMLResponse)
    def index(request: Request, repo: LedgerRepository = Depends(get_repository)) -> HTMLResponse:
        entries = repo.list_entries(limit=20)
        return templates.TemplateResponse(
            request,
            "index.html",
            {"entries": entries, "result": None},
        )

    @app.get("/api/ledger")
    def list_ledger(repo: LedgerRepository = Depends(get_repository)) -> list[dict]:
        return repo.list_entries(limit=20)

    @app.get("/api/todos")
    def list_todos(repo: LedgerRepository = Depends(get_repository)) -> list[dict]:
        return repo.list_todo_entries(limit=20)

    @app.get("/api/references")
    def list_references(repo: LedgerRepository = Depends(get_repository)) -> list[dict]:
        return repo.list_reference_entries(limit=20)

    @app.get("/api/schedules")
    def list_schedules(repo: LedgerRepository = Depends(get_repository)) -> list[dict]:
        return repo.list_schedule_entries(limit=20)

    @app.get("/api/intent-reviews", response_model=list[IntentReview])
    def list_intent_reviews(
        status: str = "pending",
        limit: int = 10,
        repo: LedgerRepository = Depends(get_repository),
    ) -> list[IntentReview]:
        resolved_status = None if status == "all" else status
        return [IntentReview.model_validate(item) for item in repo.list_intent_reviews(status=resolved_status, limit=limit)]

    @app.get("/api/ledger/{entry_id}")
    def get_ledger_entry(entry_id: int, repo: LedgerRepository = Depends(get_repository)) -> dict:
        item = repo.get_entry(entry_id)
        if item is None:
            raise HTTPException(status_code=404, detail="Ledger entry not found")
        return item

    @app.get("/api/todos/{entry_id}")
    def get_todo_entry(entry_id: int, repo: LedgerRepository = Depends(get_repository)) -> dict:
        item = repo.get_todo_entry(entry_id)
        if item is None:
            raise HTTPException(status_code=404, detail="Todo entry not found")
        return item

    @app.get("/api/references/{entry_id}")
    def get_reference_entry(entry_id: int, repo: LedgerRepository = Depends(get_repository)) -> dict:
        item = repo.get_reference_entry(entry_id)
        if item is None:
            raise HTTPException(status_code=404, detail="Reference entry not found")
        return item

    @app.get("/api/schedules/{entry_id}")
    def get_schedule_entry(entry_id: int, repo: LedgerRepository = Depends(get_repository)) -> dict:
        item = repo.get_schedule_entry(entry_id)
        if item is None:
            raise HTTPException(status_code=404, detail="Schedule entry not found")
        return item

    @app.post("/agent/life/intake", response_model=IntakeResponse)
    def intake_image(
        image: UploadFile = File(...),
        repo: LedgerRepository = Depends(get_repository),
        workflow: IntentWorkflowService = Depends(get_intent_workflow_service),
    ) -> IntakeResponse:
        response = _process_intake(
            settings=app.state.settings,
            repo=repo,
            workflow=workflow,
            image=image,
        )
        return response

    @app.post("/agent/life/mobile-intake", response_model=IntakeResponse)
    def mobile_intake(
        image: UploadFile | None = File(default=None),
        text_input: str | None = Form(default=None),
        speech_text: str | None = Form(default=None),
        speech_confidence: float | None = Form(default=None),
        page_url: str | None = Form(default=None),
        source_app: str | None = Form(default=None),
        source_type: str | None = Form(default=None),
        captured_at: str | None = Form(default=None),
        repo: LedgerRepository = Depends(get_repository),
        workflow: IntentWorkflowService = Depends(get_intent_workflow_service),
    ) -> IntakeResponse:
        response = _process_intake(
            settings=app.state.settings,
            repo=repo,
            workflow=workflow,
            image=image,
            text_input=text_input,
            speech_text=speech_text,
            speech_confidence=speech_confidence,
            page_url=page_url,
            source_app=source_app,
            source_type=source_type,
            captured_at=captured_at,
        )
        return response

    @app.post("/agent/life/mobile-intake/{review_id}/confirm", response_model=IntakeResponse)
    def confirm_mobile_intake(
        review_id: str,
        payload: ConfirmIntentRequest,
        repo: LedgerRepository = Depends(get_repository),
        workflow: IntentWorkflowService = Depends(get_intent_workflow_service),
    ) -> IntakeResponse:
        review = repo.get_intent_review(review_id)
        if review is None:
            raise HTTPException(status_code=404, detail="Intent review not found")
        if review.get("status") == "completed":
            raise HTTPException(status_code=409, detail="Intent review has already been completed")

        selected_intent = _resolve_selected_intent(payload, review.get("ranked_intents") or [])
        try:
            workflow_state = workflow.analyze(
                image_path=review.get("image_path"),
                content_type=review.get("content_type"),
                text_input=review.get("text_input"),
                speech_text=review.get("speech_text"),
                speech_confidence=review.get("speech_confidence"),
                page_url=review.get("page_url"),
                source_app=review.get("source_app"),
                source_type=review.get("source_type"),
                forced_intent=selected_intent,
            )
        except Exception as exc:
            logger.exception("Intent confirmation failed for review %s", review_id)
            detail = _describe_provider_error(exc)
            raise HTTPException(status_code=502, detail=detail) from exc

        parsed = workflow_state.get("parsed_result")
        if parsed is None:
            raise HTTPException(status_code=502, detail="Intent workflow did not produce a parsed result")

        repo.complete_intent_review(review_id, selected_intent=selected_intent)
        created_entry, executed_action = _execute_intent(
            repo,
            parsed,
            Path(review["image_path"]) if review.get("image_path") else None,
        )
        return _build_intake_response(
            parsed,
            created_entry,
            executed_action,
            ranked_intents=workflow_state.get("ranked_intents", []),
        )

    @app.post("/", response_class=HTMLResponse)
    def submit_form(
        request: Request,
        image: UploadFile = File(...),
        repo: LedgerRepository = Depends(get_repository),
        workflow: IntentWorkflowService = Depends(get_intent_workflow_service),
    ) -> HTMLResponse:
        try:
            result = _process_intake(
                settings=app.state.settings,
                repo=repo,
                workflow=workflow,
                image=image,
            )
            result = result.model_dump()
        except HTTPException as exc:
            result = {"message": exc.detail, "intent": "error"}

        entries = repo.list_entries(limit=20)
        return templates.TemplateResponse(
            request,
            "index.html",
            {"entries": entries, "result": result},
        )

    return app


def _build_intake_response(
    parsed: ScreenIntentResult,
    created_entry: dict | None,
    executed_action: str | None,
    *,
    ranked_intents: list[RankedIntentCandidate] | None = None,
    requires_confirmation: bool = False,
    review_id: str | None = None,
    confirmation_reason: str | None = None,
) -> IntakeResponse:
    if executed_action == "create_bookkeeping_entry":
        message = "Bookkeeping entry created."
    elif executed_action == "create_todo":
        message = "Todo entry created."
    elif executed_action == "save_reference":
        message = "Reference entry saved."
    elif executed_action == "schedule_event":
        message = "Schedule entry created."
    elif parsed.intent == "unknown":
        message = "No supported automation detected."
    else:
        message = f"Intent detected but not executed yet: {parsed.intent}."

    return IntakeResponse(
        intent=parsed.intent,
        confidence=parsed.confidence,
        analysis=parsed,
        parsed_receipt=parsed,
        ledger_entry=created_entry if executed_action == "create_bookkeeping_entry" else None,
        todo_entry=created_entry if executed_action == "create_todo" else None,
        reference_entry=created_entry if executed_action == "save_reference" else None,
        schedule_entry=created_entry if executed_action == "schedule_event" else None,
        executed_action=executed_action,
        requires_confirmation=requires_confirmation,
        review_id=review_id,
        ranked_intents=ranked_intents or [],
        confirmation_reason=confirmation_reason,
        message=message,
    )


def _process_intake(
    *,
    settings: Settings,
    repo: LedgerRepository,
    workflow: IntentWorkflowService,
    image: UploadFile | None = None,
    text_input: str | None = None,
    speech_text: str | None = None,
    speech_confidence: float | None = None,
    page_url: str | None = None,
    source_app: str | None = None,
    source_type: str | None = None,
    captured_at: str | None = None,
) -> IntakeResponse:
    if image is None and not any([_has_text(text_input), _has_text(speech_text), _has_text(page_url)]):
        raise HTTPException(status_code=400, detail="Provide at least one of image, text_input, speech_text, or page_url")

    saved_path = None
    content_type = None
    if image is not None:
        _validate_image_upload(image)
        saved_path = _save_upload(settings.upload_dir, image)
        content_type = image.content_type

    merged_text_input = _merge_text_input(text_input, captured_at)
    normalized_page_url = _normalize_optional_text(page_url)
    normalized_source_app = _normalize_optional_text(source_app)
    normalized_source_type = _normalize_optional_text(source_type)
    normalized_captured_at = _normalize_optional_text(captured_at)

    try:
        workflow_state = workflow.analyze(
            image_path=str(saved_path) if saved_path else None,
            content_type=content_type,
            text_input=merged_text_input,
            speech_text=_normalize_optional_text(speech_text),
            speech_confidence=_normalize_speech_confidence(speech_confidence),
            page_url=normalized_page_url,
            source_app=normalized_source_app,
            source_type=normalized_source_type,
        )
    except Exception as exc:
        logger.exception("Model provider call failed for %s", saved_path)
        detail = _describe_provider_error(exc)
        raise HTTPException(status_code=502, detail=detail) from exc

    ranked_intents = workflow_state.get("ranked_intents", [])
    if workflow_state.get("requires_confirmation"):
        primary = ranked_intents[0] if ranked_intents else RankedIntentCandidate(intent="unknown", confidence=0.0)
        review_id = repo.create_intent_review(
            image_path=str(saved_path) if saved_path else None,
            content_type=content_type,
            text_input=merged_text_input,
            speech_text=_normalize_optional_text(speech_text),
            speech_confidence=_normalize_speech_confidence(speech_confidence),
            page_url=normalized_page_url,
            source_app=normalized_source_app,
            source_type=normalized_source_type,
            captured_at=normalized_captured_at,
            ranked_intents=ranked_intents,
            confirmation_reason=workflow_state.get("confirmation_reason"),
        )
        return _build_confirmation_response(
            primary,
            ranked_intents=ranked_intents,
            review_id=review_id,
            confirmation_reason=workflow_state.get("confirmation_reason"),
        )

    parsed = workflow_state.get("parsed_result")
    if parsed is None:
        raise HTTPException(status_code=502, detail="Intent workflow did not produce a parsed result")

    created_entry, executed_action = _execute_intent(repo, parsed, saved_path)
    return _build_intake_response(
        parsed,
        created_entry,
        executed_action,
        ranked_intents=ranked_intents,
    )


def _validate_image_upload(image: UploadFile) -> None:
    if not image.content_type or not image.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Unsupported content type")


def _merge_text_input(text_input: str | None, captured_at: str | None) -> str | None:
    parts = []
    if _has_text(text_input):
        parts.append(_normalize_optional_text(text_input) or "")
    if _has_text(captured_at):
        parts.append(f"Captured at: {_normalize_optional_text(captured_at)}")
    if not parts:
        return None
    return "\n".join(parts)


def _normalize_optional_text(value: str | None) -> str | None:
    if value is None:
        return None
    stripped = value.strip()
    return stripped or None


def _has_text(value: str | None) -> bool:
    return _normalize_optional_text(value) is not None


def _normalize_speech_confidence(value: float | None) -> float | None:
    if value is None:
        return None
    return max(0.0, min(1.0, value))


def _execute_intent(
    repo: LedgerRepository,
    parsed: ScreenIntentResult,
    saved_path: Path | None,
) -> tuple[dict | None, str | None]:
    if parsed.intent == "bookkeeping":
        try:
            normalized = normalize_bookkeeping_entry(parsed)
        except ValueError as exc:
            logger.warning("Skipping bookkeeping execution: %s", exc)
            return None, None

        entry_id = repo.create_entry(
            normalized=normalized,
            intent=parsed.intent,
            source_image_path=str(saved_path or ""),
            raw_model_response=parsed.model_dump(),
        )
        return repo.get_entry(entry_id), "create_bookkeeping_entry"

    if parsed.intent == "todo":
        try:
            normalized = normalize_todo_entry(parsed)
        except ValueError as exc:
            logger.warning("Skipping todo execution: %s", exc)
            return None, None

        entry_id = repo.create_todo_entry(
            normalized=normalized,
            raw_model_response=parsed.model_dump(),
        )
        return repo.get_todo_entry(entry_id), "create_todo"

    if parsed.intent == "reference":
        try:
            normalized = normalize_reference_entry(parsed)
        except ValueError as exc:
            logger.warning("Skipping reference execution: %s", exc)
            return None, None

        entry_id = repo.create_reference_entry(
            normalized=normalized,
            raw_model_response=parsed.model_dump(),
        )
        return repo.get_reference_entry(entry_id), "save_reference"

    if parsed.intent == "schedule":
        try:
            normalized = normalize_schedule_entry(parsed)
        except ValueError as exc:
            logger.warning("Skipping schedule execution: %s", exc)
            return None, None

        entry_id = repo.create_schedule_entry(
            normalized=normalized,
            raw_model_response=parsed.model_dump(),
        )
        return repo.get_schedule_entry(entry_id), "schedule_event"

    return None, None


def _save_upload(upload_dir: Path, image: UploadFile) -> Path:
    upload_dir.mkdir(parents=True, exist_ok=True)
    suffix = Path(image.filename or "upload.bin").suffix or ".bin"
    destination = upload_dir / f"{uuid4().hex}{suffix}"
    with destination.open("wb") as file_obj:
        shutil.copyfileobj(image.file, file_obj)
    return destination


def _describe_provider_error(exc: Exception) -> str:
    message = str(exc).strip()
    if message:
        return f"Model provider call failed: {exc.__class__.__name__}: {message}"
    return f"Model provider call failed: {exc.__class__.__name__}"


def _build_confirmation_response(
    primary_candidate: RankedIntentCandidate,
    *,
    ranked_intents: list[RankedIntentCandidate],
    review_id: str,
    confirmation_reason: str | None,
) -> IntakeResponse:
    return IntakeResponse(
        intent=primary_candidate.intent,
        confidence=primary_candidate.confidence,
        analysis=None,
        parsed_receipt=None,
        ledger_entry=None,
        todo_entry=None,
        reference_entry=None,
        schedule_entry=None,
        executed_action=None,
        requires_confirmation=True,
        review_id=review_id,
        ranked_intents=ranked_intents,
        confirmation_reason=confirmation_reason,
        message="Multiple likely intents detected. Confirmation required before executing automation.",
    )


def _resolve_selected_intent(payload: ConfirmIntentRequest, ranked_intents: list[dict]) -> str:
    raw_value = payload.custom_intent or payload.selected_intent
    if raw_value is None or not raw_value.strip():
        raise HTTPException(status_code=400, detail="Provide selected_intent or custom_intent")

    normalized = raw_value.strip().lower()
    aliases = {
        "记账": "bookkeeping",
        "账单": "bookkeeping",
        "todo": "todo",
        "待办": "todo",
        "任务": "todo",
        "reference": "reference",
        "收藏": "reference",
        "保存": "reference",
        "schedule": "schedule",
        "日程": "schedule",
        "提醒": "schedule",
        "unknown": "unknown",
        "忽略": "unknown",
    }
    normalized = aliases.get(normalized, normalized)
    if normalized not in SUPPORTED_INTENTS:
        raise HTTPException(status_code=400, detail=f"Unsupported intent: {raw_value}")

    available_intents = {item.get("intent") for item in ranked_intents}
    if payload.selected_intent and normalized not in available_intents:
        raise HTTPException(status_code=400, detail="selected_intent must be one of the ranked intents")
    return normalized


app = create_app()
