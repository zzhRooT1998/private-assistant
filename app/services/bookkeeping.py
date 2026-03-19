from __future__ import annotations

from decimal import Decimal, InvalidOperation

from app.schemas import NormalizedLedgerEntry, ReceiptParseResult


def _to_decimal(value: str | None, *, default: Decimal | None = None) -> Decimal | None:
    if value is None or value == "":
        return default
    try:
        return Decimal(value)
    except InvalidOperation as exc:
        raise ValueError(f"Invalid decimal value: {value}") from exc


def normalize_bookkeeping_entry(parsed: ReceiptParseResult) -> NormalizedLedgerEntry:
    original_amount = _to_decimal(parsed.original_amount)
    discount_amount = _to_decimal(parsed.discount_amount, default=Decimal("0"))
    actual_amount = _to_decimal(parsed.actual_amount)

    if actual_amount is None:
        if original_amount is None:
            raise ValueError("Missing payable amount")
        actual_amount = original_amount - discount_amount

    if actual_amount < 0:
        raise ValueError("Payable amount cannot be negative")

    return NormalizedLedgerEntry(
        merchant=parsed.merchant,
        currency=parsed.currency,
        original_amount=original_amount,
        discount_amount=discount_amount,
        actual_amount=actual_amount,
        category=parsed.category_guess,
        occurred_at=parsed.occurred_at,
    )
