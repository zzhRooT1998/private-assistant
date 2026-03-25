from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator

SUPPORTED_INTENTS = ("bookkeeping", "todo", "reference", "schedule", "unknown")


class RankedIntentCandidate(BaseModel):
    intent: str
    confidence: float = Field(ge=0.0, le=1.0)
    reason: str | None = None
    summary: str | None = None


class IntentRankingEnvelope(BaseModel):
    candidates: list[RankedIntentCandidate]


class ScreenIntentResult(BaseModel):
    intent: str
    action: str | None = None
    confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    summary: str | None = None
    source_app: str | None = None
    source_type: str | None = None
    page_url: str | None = None
    extracted_text: str | None = None
    speech_text: str | None = None
    speech_confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    merchant: str | None = None
    currency: str | None = None
    original_amount: str | None = None
    discount_amount: str | None = None
    actual_amount: str | None = None
    category_guess: str | None = None
    occurred_at: str | None = None
    todo_title: str | None = None
    todo_details: str | None = None
    todo_due_at: str | None = None
    reference_title: str | None = None
    reference_summary: str | None = None
    schedule_title: str | None = None
    schedule_details: str | None = None
    schedule_start_at: str | None = None
    schedule_end_at: str | None = None

    @field_validator("original_amount", "discount_amount", "actual_amount", mode="before")
    @classmethod
    def coerce_amount_to_string(cls, value: Any) -> str | None:
        if value is None:
            return None
        if isinstance(value, (int, float, Decimal)):
            return str(value)
        if isinstance(value, str):
            stripped = value.strip()
            return stripped or None
        raise TypeError(f"Unsupported amount value: {value!r}")


ReceiptParseResult = ScreenIntentResult


@dataclass(slots=True)
class NormalizedLedgerEntry:
    merchant: str | None
    currency: str | None
    original_amount: Decimal | None
    discount_amount: Decimal
    actual_amount: Decimal
    category: str | None
    occurred_at: str | None


@dataclass(slots=True)
class NormalizedTodoEntry:
    title: str
    details: str | None
    due_at: str | None
    source_app: str | None
    page_url: str | None


@dataclass(slots=True)
class NormalizedReferenceEntry:
    title: str
    summary: str | None
    page_url: str | None
    source_app: str | None


@dataclass(slots=True)
class NormalizedScheduleEntry:
    title: str
    details: str | None
    start_at: str
    end_at: str | None
    source_app: str | None
    page_url: str | None


class IntakeResponse(BaseModel):
    model_config = ConfigDict(arbitrary_types_allowed=True)

    intent: str
    confidence: float
    analysis: ScreenIntentResult | None = None
    parsed_receipt: ScreenIntentResult | None = None
    ledger_entry: dict[str, Any] | None = None
    todo_entry: dict[str, Any] | None = None
    reference_entry: dict[str, Any] | None = None
    schedule_entry: dict[str, Any] | None = None
    executed_action: str | None = None
    requires_confirmation: bool = False
    review_id: str | None = None
    ranked_intents: list[RankedIntentCandidate] = Field(default_factory=list)
    confirmation_reason: str | None = None
    message: str


class ConfirmIntentRequest(BaseModel):
    selected_intent: str | None = None
    custom_intent: str | None = None


class IntentReview(BaseModel):
    id: str
    image_path: str | None = None
    content_type: str | None = None
    text_input: str | None = None
    speech_text: str | None = None
    speech_confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    page_url: str | None = None
    source_app: str | None = None
    source_type: str | None = None
    captured_at: str | None = None
    ranked_intents: list[RankedIntentCandidate] = Field(default_factory=list)
    status: str
    selected_intent: str | None = None
    confirmation_reason: str | None = None
    created_at: str
    updated_at: str
