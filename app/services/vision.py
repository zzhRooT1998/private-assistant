from __future__ import annotations

import base64
import mimetypes
import re
from pathlib import Path
from typing import Any

import httpx
from langchain_core.output_parsers import PydanticOutputParser
from langchain_core.prompts import ChatPromptTemplate
from openai import OpenAI
from pydantic import ValidationError

from app.schemas import IntentRankingEnvelope, RankedIntentCandidate, SUPPORTED_INTENTS, ScreenIntentResult


INTENT_TASK_DESCRIPTION = """You are an iPhone assistant intent parser.
Analyze the provided screenshot, shared text, URL, and source app metadata.

Intent must be one of:
- bookkeeping: clear receipt, bill, payment confirmation, or expense capture
- todo: the user likely wants to remember or act on something later
- reference: the user likely wants to save an article, product, place, or page
- schedule: the user likely wants to create or infer an event or reminder time
- unknown: not confident enough
"""


class VisionIntentService:
    BOOKKEEPING_COMMAND_PHRASES = (
        "帮我记账",
        "给我记账",
        "记一下账",
        "记这笔账",
        "记这笔",
        "记一笔",
        "记到账上",
        "记到帐上",
        "报销一下",
        "报销这笔",
        "记录这笔开销",
        "log this expense",
        "log this receipt",
        "record this expense",
        "record this receipt",
        "track this expense",
        "track this receipt",
    )
    REFERENCE_COMMAND_PHRASES = (
        "收藏这个",
        "保存这个",
        "帮我保存",
        "帮我存一下",
        "存一下",
        "记下来",
        "稍后看",
        "留着以后看",
        "bookmark this",
        "save this",
        "save for later",
        "keep this for later",
    )
    REMINDER_COMMAND_PHRASES = (
        "提醒我",
        "记得",
        "remind me",
        "remember to",
    )
    TODO_COMMAND_PHRASES = (
        "加到待办",
        "加到我的待办",
        "记成待办",
        "做个待办",
        "稍后处理",
        "回头处理",
        "之后处理",
        "晚点处理",
        "后面处理",
        "follow up on this",
        "follow up later",
        "add this to my todo",
        "add to my todo",
        "save as todo",
    )
    SCHEDULE_COMMAND_PHRASES = (
        "安排一下",
        "安排个日程",
        "创建日程",
        "加入日程",
        "加到日历",
        "放到日历",
        "约个时间",
        "预约一下",
        "约个会",
        "schedule this",
        "schedule it",
        "put this on my calendar",
        "add this to my calendar",
        "book an appointment",
        "set up a meeting",
    )
    TIME_SIGNAL_PATTERNS = (
        r"(今天|明天|后天|今晚|今早|今晨|明早|明晚|下午|上午|中午|晚上|周[一二三四五六日天]|星期[一二三四五六日天]|下周|本周)",
        r"(\d{1,2}点半|\d{1,2}点\d{1,2}分|\d{1,2}月\d{1,2}日|\d{1,2}号)",
        r"\b(today|tomorrow|tonight|this morning|this afternoon|this evening|next week)\b",
        r"\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b",
        r"\b\d{1,2}(:\d{2})?\s?(am|pm)\b",
    )

    def __init__(
        self,
        *,
        api_key: str,
        base_url: str,
        model: str,
        client: OpenAI | None = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.intent_output_parser = PydanticOutputParser(pydantic_object=ScreenIntentResult)
        self.ranking_output_parser = PydanticOutputParser(pydantic_object=IntentRankingEnvelope)
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
        speech_text: str | None = None,
        speech_confidence: float | None = None,
        page_url: str | None = None,
        source_app: str | None = None,
        source_type: str | None = None,
        forced_intent: str | None = None,
    ) -> ScreenIntentResult:
        prompt = self._build_intent_prompt(forced_intent=forced_intent)
        payload = self._run_model(
            prompt=prompt,
            image_path=image_path,
            content_type=content_type,
            text_input=text_input,
            speech_text=speech_text,
            speech_confidence=speech_confidence,
            page_url=page_url,
            source_app=source_app,
            source_type=source_type,
        )
        try:
            parsed = self.intent_output_parser.parse(payload)
        except ValidationError as exc:
            snippet = payload.strip().replace("\n", " ")[:240]
            raise ValueError(
                "Provider did not return valid intent JSON. "
                f"Raw output starts with: {snippet!r}. "
                "This usually means the selected model or endpoint does not support image understanding "
                "or did not follow the JSON-only contract."
            ) from exc
        return self._normalize_result(parsed).model_copy(
            update={
                "speech_text": speech_text,
                "speech_confidence": speech_confidence,
            }
        )

    def rank_intents(
        self,
        *,
        image_path: str | Path | None = None,
        content_type: str | None = None,
        text_input: str | None = None,
        speech_text: str | None = None,
        speech_confidence: float | None = None,
        page_url: str | None = None,
        source_app: str | None = None,
        source_type: str | None = None,
        top_k: int = 3,
    ) -> list[RankedIntentCandidate]:
        prompt = self._build_ranking_prompt(top_k=top_k)
        payload = self._run_model(
            prompt=prompt,
            image_path=image_path,
            content_type=content_type,
            text_input=text_input,
            speech_text=speech_text,
            speech_confidence=speech_confidence,
            page_url=page_url,
            source_app=source_app,
            source_type=source_type,
        )
        try:
            envelope = self.ranking_output_parser.parse(payload)
        except ValidationError as exc:
            snippet = payload.strip().replace("\n", " ")[:240]
            raise ValueError(
                "Provider did not return valid intent ranking JSON. "
                f"Raw output starts with: {snippet!r}."
            ) from exc

        normalized: list[RankedIntentCandidate] = []
        seen_intents: set[str] = set()
        for candidate in envelope.candidates:
            intent = (candidate.intent or "unknown").strip().lower()
            if intent not in SUPPORTED_INTENTS:
                intent = "unknown"
            if intent in seen_intents:
                continue
            seen_intents.add(intent)
            normalized.append(
                candidate.model_copy(
                    update={
                        "intent": intent,
                        "confidence": max(0.0, min(1.0, candidate.confidence)),
                    }
                )
            )
            if len(normalized) == top_k:
                break

        if not normalized:
            normalized = [RankedIntentCandidate(intent="unknown", confidence=0.0, reason="No ranking returned.")]
        return normalized

    def parse_receipt(self, image_path: str | Path, content_type: str | None = None) -> ScreenIntentResult:
        return self.parse_input(image_path=image_path, content_type=content_type)

    def infer_explicit_speech_intent(
        self,
        *,
        speech_text: str | None,
        speech_confidence: float | None,
    ) -> str | None:
        return self._infer_explicit_speech_intent_from_signal(
            speech_text=speech_text,
            speech_confidence=speech_confidence,
        )

    def prioritize_speech_intent(
        self,
        ranked_intents: list[RankedIntentCandidate],
        *,
        speech_intent: str,
    ) -> list[RankedIntentCandidate]:
        if speech_intent not in SUPPORTED_INTENTS:
            return ranked_intents

        speech_candidate = next((candidate for candidate in ranked_intents if candidate.intent == speech_intent), None)
        others = [candidate for candidate in ranked_intents if candidate.intent != speech_intent]
        if speech_candidate is None:
            speech_candidate = RankedIntentCandidate(
                intent=speech_intent,
                confidence=0.91,
                reason="Explicit speech command takes priority over screenshot context.",
                summary="Speech command overrides ambiguous visual context.",
            )
        else:
            speech_candidate = speech_candidate.model_copy(
                update={
                    "confidence": max(speech_candidate.confidence, 0.91),
                    "reason": "Explicit speech command takes priority over screenshot context.",
                }
            )
        return [speech_candidate, *others][:3]

    def _build_intent_prompt(self, *, forced_intent: str | None) -> str:
        extra_rules = [
            "Return strict JSON for a ScreenIntentResult object.",
            self.intent_output_parser.get_format_instructions(),
            "Use null for missing fields.",
            "When a valid spoken command is present, treat speech as the primary signal of user intent. Treat the screenshot as supporting evidence for extraction and grounding.",
        ]
        if forced_intent:
            extra_rules.append(
                f"The user or upstream workflow has already chosen the intent '{forced_intent}'. "
                "Do not re-rank intents. Extract fields only for that chosen intent."
            )
        return ChatPromptTemplate.from_messages(
            [
                (
                    "system",
                    "{task_description}\n\n{extra_rules}",
                ),
            ]
        ).format_messages(
            task_description=INTENT_TASK_DESCRIPTION,
            extra_rules="\n".join(extra_rules),
        )[0].content

    def _build_ranking_prompt(self, *, top_k: int) -> str:
        return ChatPromptTemplate.from_messages(
            [
                (
                    "system",
                    "{task_description}\n\n"
                    "Rank the top {top_k} most likely user intents for this mobile capture. "
                    "When a valid spoken command is present, speech should outweigh conflicting screenshot context. "
                    "Return strict JSON with a single key `candidates`, ordered from highest to lowest confidence. "
                    "Each candidate must include: intent, confidence, reason, summary.\n"
                    "{format_instructions}",
                )
            ]
        ).format_messages(
            task_description=INTENT_TASK_DESCRIPTION,
            top_k=str(top_k),
            format_instructions=self.ranking_output_parser.get_format_instructions(),
        )[0].content

    def _run_model(
        self,
        *,
        prompt: str,
        image_path: str | Path | None,
        content_type: str | None,
        text_input: str | None,
        speech_text: str | None,
        speech_confidence: float | None,
        page_url: str | None,
        source_app: str | None,
        source_type: str | None,
    ) -> str:
        user_content = self._build_user_content(
            image_path=image_path,
            content_type=content_type,
            text_input=text_input,
            speech_text=speech_text,
            speech_confidence=speech_confidence,
            page_url=page_url,
            source_app=source_app,
            source_type=source_type,
        )

        if self._uses_dashscope_chat_completions():
            response = self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": prompt},
                    {"role": "user", "content": self._to_chat_completion_content(user_content)},
                ],
            )
            payload = self._extract_chat_completion_text(response)
        else:
            response = self.client.responses.create(
                model=self.model,
                input=[
                    {
                        "role": "system",
                        "content": [{"type": "input_text", "text": prompt}],
                    },
                    {
                        "role": "user",
                        "content": user_content,
                    },
                ],
            )
            payload = self._extract_output_text(response)
        return self._extract_json_text(payload)

    def _build_user_content(
        self,
        *,
        image_path: str | Path | None,
        content_type: str | None,
        text_input: str | None,
        speech_text: str | None,
        speech_confidence: float | None,
        page_url: str | None,
        source_app: str | None,
        source_type: str | None,
    ) -> list[dict[str, str]]:
        user_content: list[dict[str, str]] = []

        context_lines = [
            "Analyze this mobile capture and infer the user's intent.",
            f"Source app: {source_app or 'unknown'}",
            f"Source type: {source_type or 'unknown'}",
            f"Page URL: {page_url or 'unknown'}",
        ]
        if text_input:
            context_lines.append(f"Shared text:\n{text_input}")
        if speech_text:
            confidence_text = "unknown" if speech_confidence is None else f"{speech_confidence:.2f}"
            context_lines.append(f"Spoken command (primary intent signal, confidence={confidence_text}):\n{speech_text}")
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
        return user_content

    def _uses_dashscope_chat_completions(self) -> bool:
        return "dashscope" in self.base_url and self.base_url.endswith("/compatible-mode/v1")

    @staticmethod
    def _to_chat_completion_content(user_content: list[dict[str, str]]) -> list[dict[str, Any]]:
        content: list[dict[str, Any]] = []
        for item in user_content:
            if item["type"] == "input_text":
                content.append({"type": "text", "text": item["text"]})
            elif item["type"] == "input_image":
                content.append(
                    {
                        "type": "image_url",
                        "image_url": {"url": item["image_url"]},
                    }
                )
        return content

    @staticmethod
    def _extract_chat_completion_text(response: Any) -> str:
        choices = VisionIntentService._field(response, "choices") or []
        for choice in choices:
            message = VisionIntentService._field(choice, "message")
            content = VisionIntentService._field(message, "content")
            text = VisionIntentService._coerce_chat_content_text(content)
            if text:
                return text

        error = VisionIntentService._field(response, "error")
        error_message = VisionIntentService._field(error, "message")
        if error_message:
            raise ValueError(str(error_message))

        snippet = repr(response)[:240]
        raise ValueError(f"Model chat completion did not include text output. Raw response starts with: {snippet}")

    @staticmethod
    def _extract_output_text(response: Any) -> str:
        direct_output_text = VisionIntentService._coerce_output_text(
            VisionIntentService._field(response, "output_text")
        )
        if direct_output_text:
            return direct_output_text

        output_items = VisionIntentService._field(response, "output") or []
        for item in output_items:
            item_text = VisionIntentService._coerce_output_text(
                VisionIntentService._field(item, "output_text")
            )
            if item_text:
                return item_text

            content = VisionIntentService._field(item, "content") or []
            for chunk in content:
                chunk_text = VisionIntentService._coerce_output_text(
                    VisionIntentService._field(chunk, "text")
                )
                if chunk_text:
                    return chunk_text

                chunk_text = VisionIntentService._coerce_output_text(
                    VisionIntentService._field(chunk, "output_text")
                )
                if chunk_text:
                    return chunk_text

        model_dump = getattr(response, "model_dump", None)
        if callable(model_dump):
            recursive_text = VisionIntentService._find_text_value(model_dump())
            if recursive_text:
                return recursive_text

        recursive_text = VisionIntentService._find_text_value(response)
        if recursive_text:
            return recursive_text

        snippet = repr(response)[:240]
        raise ValueError(f"Model response did not include text output. Raw response starts with: {snippet}")

    @staticmethod
    def _field(value: Any, key: str) -> Any:
        if value is None:
            return None
        if isinstance(value, dict):
            return value.get(key)
        return getattr(value, key, None)

    @staticmethod
    def _coerce_output_text(value: Any) -> str | None:
        if value is None:
            return None
        if isinstance(value, str):
            stripped = value.strip()
            return stripped or None
        if isinstance(value, list):
            parts = [part for item in value if (part := VisionIntentService._coerce_output_text(item))]
            if parts:
                return "\n".join(parts)
            return None
        if isinstance(value, dict):
            text = VisionIntentService._field(value, "text")
            if isinstance(text, str) and text.strip():
                return text.strip()
        text = getattr(value, "text", None)
        if isinstance(text, str) and text.strip():
            return text.strip()
        return None

    @staticmethod
    def _coerce_chat_content_text(value: Any) -> str | None:
        if value is None:
            return None
        if isinstance(value, str):
            stripped = value.strip()
            return stripped or None
        if isinstance(value, list):
            parts: list[str] = []
            for item in value:
                if isinstance(item, dict):
                    text = VisionIntentService._field(item, "text")
                    if isinstance(text, str) and text.strip():
                        parts.append(text.strip())
                else:
                    text = VisionIntentService._coerce_chat_content_text(item)
                    if text:
                        parts.append(text)
            if parts:
                return "\n".join(parts)
        return None

    @staticmethod
    def _find_text_value(value: Any) -> str | None:
        if value is None:
            return None
        if isinstance(value, str):
            stripped = value.strip()
            if stripped.startswith("{") and stripped.endswith("}"):
                return stripped
            return None
        if isinstance(value, dict):
            for preferred_key in ("output_text", "text"):
                preferred_value = value.get(preferred_key)
                coerced = VisionIntentService._coerce_output_text(preferred_value)
                if coerced:
                    return coerced
            for nested in value.values():
                found = VisionIntentService._find_text_value(nested)
                if found:
                    return found
            return None
        if isinstance(value, list):
            for nested in value:
                found = VisionIntentService._find_text_value(nested)
                if found:
                    return found
            return None
        if hasattr(value, "__dict__"):
            return VisionIntentService._find_text_value(vars(value))
        return None

    @staticmethod
    def _normalize_free_text(value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.strip().lower().split())
        return normalized or None

    @staticmethod
    def _count_matches(text: str, keywords: tuple[str, ...]) -> int:
        return sum(1 for keyword in keywords if keyword in text)

    @classmethod
    def _infer_explicit_speech_intent_from_signal(
        cls,
        *,
        speech_text: str | None,
        speech_confidence: float | None,
    ) -> str | None:
        normalized = cls._normalize_free_text(speech_text)
        if normalized is None:
            return None
        if speech_confidence is not None and speech_confidence < 0.55:
            return None
        return cls._parse_explicit_speech_command(normalized)

    @classmethod
    def _parse_explicit_speech_command(cls, text: str) -> str | None:
        has_time_signal = cls._contains_time_signal(text)

        if cls._contains_any_phrase(text, cls.BOOKKEEPING_COMMAND_PHRASES):
            return "bookkeeping"

        if cls._contains_any_phrase(text, cls.REFERENCE_COMMAND_PHRASES):
            return "reference"

        if cls._contains_any_phrase(text, cls.REMINDER_COMMAND_PHRASES):
            return "schedule" if has_time_signal else "todo"

        if cls._contains_any_phrase(text, cls.SCHEDULE_COMMAND_PHRASES):
            return "schedule"

        if cls._contains_any_phrase(text, cls.TODO_COMMAND_PHRASES):
            return "todo"

        return None

    @classmethod
    def _contains_time_signal(cls, text: str) -> bool:
        return any(re.search(pattern, text) for pattern in cls.TIME_SIGNAL_PATTERNS)

    @staticmethod
    def _contains_any_phrase(text: str, phrases: tuple[str, ...]) -> bool:
        return any(phrase in text for phrase in phrases)

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
        if intent not in SUPPORTED_INTENTS:
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
    def __init__(
        self,
        result: ScreenIntentResult,
        ranked_intents: list[RankedIntentCandidate] | None = None,
    ):
        self.result = result
        self.ranked_intents = ranked_intents or [
            RankedIntentCandidate(
                intent=result.intent,
                confidence=result.confidence or 0.0,
                summary=result.summary,
                reason="Stub candidate derived from result.",
            )
        ]

    def parse_input(
        self,
        *,
        image_path: str | Path | None = None,
        content_type: str | None = None,
        text_input: str | None = None,
        speech_text: str | None = None,
        speech_confidence: float | None = None,
        page_url: str | None = None,
        source_app: str | None = None,
        source_type: str | None = None,
        forced_intent: str | None = None,
    ) -> ScreenIntentResult:
        if forced_intent:
            return self.result.model_copy(
                deep=True,
                update={
                    "intent": forced_intent,
                    "speech_text": speech_text,
                    "speech_confidence": speech_confidence,
                },
            )
        return self.result.model_copy(
            deep=True,
            update={"speech_text": speech_text, "speech_confidence": speech_confidence},
        )

    def rank_intents(
        self,
        *,
        image_path: str | Path | None = None,
        content_type: str | None = None,
        text_input: str | None = None,
        speech_text: str | None = None,
        speech_confidence: float | None = None,
        page_url: str | None = None,
        source_app: str | None = None,
        source_type: str | None = None,
        top_k: int = 3,
    ) -> list[RankedIntentCandidate]:
        return [candidate.model_copy(deep=True) for candidate in self.ranked_intents[:top_k]]

    def infer_explicit_speech_intent(
        self,
        *,
        speech_text: str | None,
        speech_confidence: float | None,
    ) -> str | None:
        return VisionIntentService._infer_explicit_speech_intent_from_signal(
            speech_text=speech_text,
            speech_confidence=speech_confidence,
        )

    def prioritize_speech_intent(
        self,
        ranked_intents: list[RankedIntentCandidate],
        *,
        speech_intent: str,
    ) -> list[RankedIntentCandidate]:
        speech_candidate = next((candidate for candidate in ranked_intents if candidate.intent == speech_intent), None)
        others = [candidate for candidate in ranked_intents if candidate.intent != speech_intent]
        if speech_candidate is None:
            speech_candidate = RankedIntentCandidate(intent=speech_intent, confidence=0.91, reason="Speech override.")
        else:
            speech_candidate = speech_candidate.model_copy(update={"confidence": max(speech_candidate.confidence, 0.91)})
        return [speech_candidate, *others][:3]

    def parse_receipt(self, image_path: str | Path, content_type: str | None = None) -> ScreenIntentResult:
        return self.result.model_copy(deep=True)
