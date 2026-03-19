from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator


class ReceiptParseResult(BaseModel):
    intent: str
    confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    merchant: str | None = None
    currency: str | None = None
    original_amount: str | None = None
    discount_amount: str | None = None
    actual_amount: str | None = None
    category_guess: str | None = None
    occurred_at: str | None = None

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


@dataclass(slots=True)
class NormalizedLedgerEntry:
    merchant: str | None
    currency: str | None
    original_amount: Decimal | None
    discount_amount: Decimal
    actual_amount: Decimal
    category: str | None
    occurred_at: str | None


class IntakeResponse(BaseModel):
    model_config = ConfigDict(arbitrary_types_allowed=True)

    intent: str
    confidence: float
    parsed_receipt: ReceiptParseResult | None = None
    ledger_entry: dict[str, Any] | None = None
    message: str
