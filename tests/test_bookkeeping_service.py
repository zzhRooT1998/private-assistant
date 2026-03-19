from decimal import Decimal

import pytest

from app.schemas import ReceiptParseResult
from app.services.bookkeeping import normalize_bookkeeping_entry


def test_uses_actual_amount_when_present():
    parsed = ReceiptParseResult(
        intent="bookkeeping",
        confidence=0.9,
        merchant="Lunch",
        currency="CNY",
        original_amount="32.00",
        discount_amount="5.00",
        actual_amount="27.00",
        category_guess="food",
        occurred_at=None,
    )

    entry = normalize_bookkeeping_entry(parsed)

    assert entry.actual_amount == Decimal("27.00")
    assert entry.discount_amount == Decimal("5.00")


def test_computes_actual_amount_from_original_minus_discount():
    parsed = ReceiptParseResult(
        intent="bookkeeping",
        confidence=0.9,
        merchant="Store",
        currency="CNY",
        original_amount="100.00",
        discount_amount="20.50",
        actual_amount=None,
        category_guess="shopping",
        occurred_at=None,
    )

    entry = normalize_bookkeeping_entry(parsed)

    assert entry.actual_amount == Decimal("79.50")


def test_rejects_negative_amount():
    parsed = ReceiptParseResult(
        intent="bookkeeping",
        confidence=0.9,
        merchant="Store",
        currency="CNY",
        original_amount="10.00",
        discount_amount="20.50",
        actual_amount=None,
        category_guess="shopping",
        occurred_at=None,
    )

    with pytest.raises(ValueError):
        normalize_bookkeeping_entry(parsed)
