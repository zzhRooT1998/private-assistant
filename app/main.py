from __future__ import annotations

import logging
import shutil
from pathlib import Path
from uuid import uuid4

from fastapi import Depends, FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from app.config import Settings, get_settings
from app.db import init_db
from app.repository import LedgerRepository
from app.schemas import IntakeResponse, ReceiptParseResult
from app.services.bookkeeping import normalize_bookkeeping_entry
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

    @app.get("/api/ledger/{entry_id}")
    def get_ledger_entry(entry_id: int, repo: LedgerRepository = Depends(get_repository)) -> dict:
        item = repo.get_entry(entry_id)
        if item is None:
            raise HTTPException(status_code=404, detail="Ledger entry not found")
        return item

    @app.post("/agent/life/intake", response_model=IntakeResponse)
    def intake_image(
        image: UploadFile = File(...),
        repo: LedgerRepository = Depends(get_repository),
        vision: VisionIntentService = Depends(get_vision_service),
    ) -> IntakeResponse:
        parsed, ledger_entry = _process_upload(app.state.settings, repo, vision, image)
        if parsed.intent != "bookkeeping":
            return IntakeResponse(
                intent=parsed.intent,
                confidence=parsed.confidence,
                parsed_receipt=parsed,
                ledger_entry=None,
                message="No bookkeeping entry created.",
            )

        return IntakeResponse(
            intent=parsed.intent,
            confidence=parsed.confidence,
            parsed_receipt=parsed,
            ledger_entry=ledger_entry,
            message="Bookkeeping entry created.",
        )

    @app.post("/", response_class=HTMLResponse)
    def submit_form(
        request: Request,
        image: UploadFile = File(...),
        repo: LedgerRepository = Depends(get_repository),
        vision: VisionIntentService = Depends(get_vision_service),
    ) -> HTMLResponse:
        try:
            parsed, ledger_entry = _process_upload(app.state.settings, repo, vision, image)
            result = {
                "intent": parsed.intent,
                "confidence": parsed.confidence,
                "parsed_receipt": parsed.model_dump(),
                "ledger_entry": ledger_entry,
                "message": (
                    "Bookkeeping entry created."
                    if parsed.intent == "bookkeeping"
                    else "No bookkeeping entry created."
                ),
            }
        except HTTPException as exc:
            result = {"message": exc.detail, "intent": "error"}

        entries = repo.list_entries(limit=20)
        return templates.TemplateResponse(
            request,
            "index.html",
            {"entries": entries, "result": result},
        )

    return app


def _process_upload(
    settings: Settings,
    repo: LedgerRepository,
    vision: VisionIntentService,
    image: UploadFile,
) -> tuple[ReceiptParseResult, dict | None]:
    if not image.content_type or not image.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Unsupported content type")

    saved_path = _save_upload(settings.upload_dir, image)

    try:
        parsed = vision.parse_receipt(saved_path, content_type=image.content_type)
    except Exception as exc:
        logger.exception("Model provider call failed for %s", saved_path)
        detail = _describe_provider_error(exc)
        raise HTTPException(status_code=502, detail=detail) from exc

    if parsed.intent != "bookkeeping":
        return parsed, None

    try:
        normalized = normalize_bookkeeping_entry(parsed)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    entry_id = repo.create_entry(
        normalized=normalized,
        intent=parsed.intent,
        source_image_path=str(saved_path),
        raw_model_response=parsed.model_dump(),
    )
    return parsed, repo.get_entry(entry_id)


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
