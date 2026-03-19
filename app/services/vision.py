from __future__ import annotations

import base64
import mimetypes
from pathlib import Path
from typing import Any

import httpx
from openai import OpenAI
from pydantic import ValidationError

from app.schemas import ReceiptParseResult


PROMPT = """You are a receipt intent parser.
Return strict JSON with keys:
intent, confidence, merchant, currency, original_amount, discount_amount, actual_amount, category_guess, occurred_at.
Set intent to bookkeeping only for clear receipts or bills, otherwise unknown.
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

    def parse_receipt(self, image_path: str | Path, content_type: str | None = None) -> ReceiptParseResult:
        path = Path(image_path)
        image_bytes = path.read_bytes()
        image_b64 = base64.b64encode(image_bytes).decode("ascii")
        mime_type = content_type or mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        response = self.client.responses.create(
            model=self.model,
            input=[
                {
                    "role": "system",
                    "content": [{"type": "input_text", "text": PROMPT}],
                },
                {
                    "role": "user",
                    "content": [
                        {"type": "input_text", "text": "Parse this image."},
                        {
                            "type": "input_image",
                            "image_url": f"data:{mime_type};base64,{image_b64}",
                        },
                    ],
                },
            ],
        )
        payload = self._extract_output_text(response)
        payload = self._extract_json_text(payload)
        try:
            parsed = ReceiptParseResult.model_validate_json(payload)
        except ValidationError as exc:
            snippet = payload.strip().replace("\n", " ")[:240]
            raise ValueError(
                "Provider did not return valid receipt JSON. "
                f"Raw output starts with: {snippet!r}. "
                "This usually means the selected model or endpoint does not support image understanding "
                "or did not follow the JSON-only contract."
            ) from exc
        return self._normalize_result(parsed)

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
    def _normalize_result(parsed: ReceiptParseResult) -> ReceiptParseResult:
        confidence = parsed.confidence
        if confidence is None:
            confidence = 0.0
        intent = (parsed.intent or "unknown").strip().lower()
        if intent not in {"bookkeeping", "unknown"}:
            intent = "unknown"
        return parsed.model_copy(
            update={
                "intent": intent,
                "confidence": confidence,
            }
        )


class StubVisionIntentService:
    def __init__(self, result: ReceiptParseResult):
        self.result = result

    def parse_receipt(self, image_path: str | Path, content_type: str | None = None) -> ReceiptParseResult:
        return self.result.model_copy(deep=True)
