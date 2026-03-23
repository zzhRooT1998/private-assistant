from __future__ import annotations

import base64
import mimetypes
from pathlib import Path
from typing import Any

import httpx
from openai import OpenAI
from pydantic import ValidationError

from app.schemas import ScreenIntentResult


PROMPT = """You are an iPhone assistant intent parser.
Analyze the provided screenshot, shared text, URL, and source app metadata.
Return strict JSON with keys:
intent, action, confidence, summary, source_app, source_type, page_url, extracted_text, merchant, currency, original_amount, discount_amount, actual_amount, category_guess, occurred_at, todo_title, todo_details, todo_due_at, reference_title, reference_summary, schedule_title, schedule_details, schedule_start_at, schedule_end_at.

Intent must be one of:
- bookkeeping: clear receipt, bill, payment confirmation, or expense capture
- todo: the user likely wants to remember or act on something later
- reference: the user likely wants to save an article, product, place, or page
- schedule: the user likely wants to create or infer an event or reminder time
- unknown: not confident enough

Action must be one of:
- create_bookkeeping_entry
- create_todo
- save_reference
- schedule_event
- none

Use bookkeeping fields only when intent=bookkeeping.
Use todo fields only when intent=todo.
Use reference fields only when intent=reference.
Use schedule fields only when intent=schedule.
Use null for missing fields.
"""


class VisionIntentService:
    def __init__(
        self,
        *,
        api_key: str,
        base_url: str,
        model: str,
        client: OpenAI | None = None,
    ) -> None:
        self.model = model
        self.client = client or OpenAI(
            api_key=api_key,
            base_url=base_url,
            http_client=httpx.Client(trust_env=False),
        )

    def parse_input(
        self,
        *,
        image_path: str | Path | None = None,
        content_type: str | None = None,
        text_input: str | None = None,
        page_url: str | None = None,
        source_app: str | None = None,
        source_type: str | None = None,
    ) -> ScreenIntentResult:
        user_content: list[dict[str, str]] = []

        context_lines = [
            "Analyze this mobile capture and infer the user's intent.",
            f"Source app: {source_app or 'unknown'}",
            f"Source type: {source_type or 'unknown'}",
            f"Page URL: {page_url or 'unknown'}",
        ]
        if text_input:
            context_lines.append(f"Shared text:\n{text_input}")
        user_content.append({"type": "input_text", "text": "\n".join(context_lines)})

        if image_path is not None:
            path = Path(image_path)
            image_bytes = path.read_bytes()
            image_b64 = base64.b64encode(image_bytes).decode("ascii")
            mime_type = content_type or mimetypes.guess_type(path.name)[0] or "application/octet-stream"
            user_content.append(
                {
                    "type": "input_image",
                    "image_url": f"data:{mime_type};base64,{image_b64}",
                }
            )

        response = self.client.responses.create(
            model=self.model,
            input=[
                {
                    "role": "system",
                    "content": [{"type": "input_text", "text": PROMPT}],
                },
                {
                    "role": "user",
                    "content": user_content,
                },
            ],
        )
        payload = self._extract_output_text(response)
        payload = self._extract_json_text(payload)
        try:
            parsed = ScreenIntentResult.model_validate_json(payload)
        except ValidationError as exc:
            snippet = payload.strip().replace("\n", " ")[:240]
            raise ValueError(
                "Provider did not return valid intent JSON. "
                f"Raw output starts with: {snippet!r}. "
                "This usually means the selected model or endpoint does not support image understanding "
                "or did not follow the JSON-only contract."
            ) from exc
        return self._normalize_result(parsed)

    def parse_receipt(self, image_path: str | Path, content_type: str | None = None) -> ScreenIntentResult:
        return self.parse_input(image_path=image_path, content_type=content_type)

    @staticmethod
    def _extract_output_text(response: Any) -> str:
        output_text = getattr(response, "output_text", None)
        if output_text:
            return output_text

        if hasattr(response, "output"):
            for item in response.output:
                content = getattr(item, "content", None) or []
                for chunk in content:
                    text = getattr(chunk, "text", None)
                    if text:
                        return text

        raise ValueError("Model response did not include text output")

    @staticmethod
    def _extract_json_text(text: str) -> str:
        stripped = text.strip()
        if stripped.startswith("```"):
            lines = stripped.splitlines()
            if len(lines) >= 3:
                stripped = "\n".join(lines[1:-1]).strip()

        start = stripped.find("{")
        end = stripped.rfind("}")
        if start != -1 and end != -1 and end > start:
            return stripped[start:end + 1]
        return stripped

    @staticmethod
    def _normalize_result(parsed: ScreenIntentResult) -> ScreenIntentResult:
        confidence = parsed.confidence
        if confidence is None:
            confidence = 0.0
        intent = (parsed.intent or "unknown").strip().lower()
        if intent not in {"bookkeeping", "todo", "reference", "schedule", "unknown"}:
            intent = "unknown"

        action = (parsed.action or "").strip().lower() or None
        if action not in {
            "create_bookkeeping_entry",
            "create_todo",
            "save_reference",
            "schedule_event",
            "none",
            None,
        }:
            action = "none"
        if action in {None, "none"}:
            action = {
                "bookkeeping": "create_bookkeeping_entry",
                "todo": "create_todo",
                "reference": "save_reference",
                "schedule": "schedule_event",
            }.get(intent, "none")

        return parsed.model_copy(
            update={
                "intent": intent,
                "action": action,
                "confidence": confidence,
            }
        )


class StubVisionIntentService:
    def __init__(self, result: ScreenIntentResult):
        self.result = result

    def parse_input(
        self,
        *,
        image_path: str | Path | None = None,
        content_type: str | None = None,
        text_input: str | None = None,
        page_url: str | None = None,
        source_app: str | None = None,
        source_type: str | None = None,
    ) -> ScreenIntentResult:
        return self.result.model_copy(deep=True)

    def parse_receipt(self, image_path: str | Path, content_type: str | None = None) -> ScreenIntentResult:
        return self.result.model_copy(deep=True)
