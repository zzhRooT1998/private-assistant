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
from app.schemas import IntakeResponse, ScreenIntentResult
from app.services.bookkeeping import normalize_bookkeeping_entry
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
        vision: VisionIntentService = Depends(get_vision_service),
    ) -> IntakeResponse:
        parsed, ledger_entry, executed_action = _process_intake(
            settings=app.state.settings,
            repo=repo,
            vision=vision,
            image=image,
        )
        return _build_intake_response(parsed, ledger_entry, executed_action)

    @app.post("/agent/life/mobile-intake", response_model=IntakeResponse)
    def mobile_intake(
        image: UploadFile | None = File(default=None),
        text_input: str | None = Form(default=None),
        page_url: str | None = Form(default=None),
        source_app: str | None = Form(default=None),
        source_type: str | None = Form(default=None),
        captured_at: str | None = Form(default=None),
        repo: LedgerRepository = Depends(get_repository),
        vision: VisionIntentService = Depends(get_vision_service),
    ) -> IntakeResponse:
        parsed, ledger_entry, executed_action = _process_intake(
            settings=app.state.settings,
            repo=repo,
            vision=vision,
            image=image,
            text_input=text_input,
            page_url=page_url,
            source_app=source_app,
            source_type=source_type,
            captured_at=captured_at,
        )
        return _build_intake_response(parsed, ledger_entry, executed_action)

    @app.post("/", response_class=HTMLResponse)
    def submit_form(
        request: Request,
        image: UploadFile = File(...),
        repo: LedgerRepository = Depends(get_repository),
        vision: VisionIntentService = Depends(get_vision_service),
    ) -> HTMLResponse:
        try:
            parsed, ledger_entry, executed_action = _process_intake(
                settings=app.state.settings,
                repo=repo,
                vision=vision,
                image=image,
            )
            result = _build_intake_response(parsed, ledger_entry, executed_action).model_dump()
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
        message=message,
    )


def _process_intake(
    *,
    settings: Settings,
    repo: LedgerRepository,
    vision: VisionIntentService,
    image: UploadFile | None = None,
    text_input: str | None = None,
    page_url: str | None = None,
    source_app: str | None = None,
    source_type: str | None = None,
    captured_at: str | None = None,
) -> tuple[ScreenIntentResult, dict | None, str | None]:
    if image is None and not any([_has_text(text_input), _has_text(page_url)]):
        raise HTTPException(status_code=400, detail="Provide at least one of image, text_input, or page_url")

    saved_path = None
    content_type = None
    if image is not None:
        _validate_image_upload(image)
        saved_path = _save_upload(settings.upload_dir, image)
        content_type = image.content_type

    try:
        parsed = vision.parse_input(
            image_path=saved_path,
            content_type=content_type,
            text_input=_merge_text_input(text_input, captured_at),
            page_url=_normalize_optional_text(page_url),
            source_app=_normalize_optional_text(source_app),
            source_type=_normalize_optional_text(source_type),
        )
    except Exception as exc:
        logger.exception("Model provider call failed for %s", saved_path)
        detail = _describe_provider_error(exc)
        raise HTTPException(status_code=502, detail=detail) from exc

    return _execute_intent(repo, parsed, saved_path)


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


def _execute_intent(
    repo: LedgerRepository,
    parsed: ScreenIntentResult,
    saved_path: Path | None,
) -> tuple[ScreenIntentResult, dict | None, str | None]:
    if parsed.intent == "bookkeeping":
        try:
            normalized = normalize_bookkeeping_entry(parsed)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc

        entry_id = repo.create_entry(
            normalized=normalized,
            intent=parsed.intent,
            source_image_path=str(saved_path or ""),
            raw_model_response=parsed.model_dump(),
        )
        return parsed, repo.get_entry(entry_id), "create_bookkeeping_entry"

    if parsed.intent == "todo":
        try:
            normalized = normalize_todo_entry(parsed)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc

        entry_id = repo.create_todo_entry(
            normalized=normalized,
            raw_model_response=parsed.model_dump(),
        )
        return parsed, repo.get_todo_entry(entry_id), "create_todo"

    if parsed.intent == "reference":
        try:
            normalized = normalize_reference_entry(parsed)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc

        entry_id = repo.create_reference_entry(
            normalized=normalized,
            raw_model_response=parsed.model_dump(),
        )
        return parsed, repo.get_reference_entry(entry_id), "save_reference"

    if parsed.intent == "schedule":
        try:
            normalized = normalize_schedule_entry(parsed)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc

        entry_id = repo.create_schedule_entry(
            normalized=normalized,
            raw_model_response=parsed.model_dump(),
        )
        return parsed, repo.get_schedule_entry(entry_id), "schedule_event"

    return parsed, None, None


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


app = create_app()
