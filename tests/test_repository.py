from decimal import Decimal

from app.db import init_db
from app.repository import LedgerRepository
from app.schemas import NormalizedLedgerEntry


def test_inserts_and_lists_ledger_entries(tmp_path):
    db_path = tmp_path / "ledger.db"
    init_db(db_path)
    repo = LedgerRepository(db_path)

    entry_id = repo.create_entry(
        normalized=NormalizedLedgerEntry(
            merchant="Coffee",
            currency="CNY",
            original_amount=None,
            discount_amount=Decimal("0"),
            actual_amount=Decimal("18"),
            category="food",
            occurred_at=None,
        ),
        intent="bookkeeping",
        source_image_path="uploads/test.jpg",
        raw_model_response={"intent": "bookkeeping"},
    )

    items = repo.list_entries(limit=10)

    assert entry_id == 1
    assert len(items) == 1
    assert items[0]["merchant"] == "Coffee"


def test_get_entry_returns_full_item(tmp_path):
    db_path = tmp_path / "ledger.db"
    init_db(db_path)
    repo = LedgerRepository(db_path)

    entry_id = repo.create_entry(
        normalized=NormalizedLedgerEntry(
            merchant="Bakery",
            currency="CNY",
            original_amount=Decimal("21.50"),
            discount_amount=Decimal("1.50"),
            actual_amount=Decimal("20.00"),
            category="food",
            occurred_at="2026-03-19T08:30:00+08:00",
        ),
        intent="bookkeeping",
        source_image_path="uploads/test.jpg",
        raw_model_response={"intent": "bookkeeping", "merchant": "Bakery"},
    )

    item = repo.get_entry(entry_id)

    assert item is not None
    assert item["actual_amount"] == "20.00"
    assert item["raw_model_response"]["merchant"] == "Bakery"
