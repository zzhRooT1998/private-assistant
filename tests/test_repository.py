from decimal import Decimal

from app.db import init_db
from app.repository import LedgerRepository
from app.schemas import (
    NormalizedLedgerEntry,
    NormalizedReferenceEntry,
    NormalizedScheduleEntry,
    NormalizedTodoEntry,
)


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


def test_inserts_non_bookkeeping_entries(tmp_path):
    db_path = tmp_path / "ledger.db"
    init_db(db_path)
    repo = LedgerRepository(db_path)

    todo_id = repo.create_todo_entry(
        normalized=NormalizedTodoEntry(
            title="Reply to message",
            details="Send the revised deck tonight.",
            due_at="2026-03-23T22:00:00+08:00",
            source_app="WeChat",
            page_url="https://example.com/chat/123",
        ),
        raw_model_response={"intent": "todo"},
    )
    reference_id = repo.create_reference_entry(
        normalized=NormalizedReferenceEntry(
            title="Interesting article",
            summary="Save this article for later.",
            page_url="https://example.com/article",
            source_app="Safari",
        ),
        raw_model_response={"intent": "reference"},
    )
    schedule_id = repo.create_schedule_entry(
        normalized=NormalizedScheduleEntry(
            title="Dentist appointment",
            details="Dentist at 3pm tomorrow",
            start_at="2026-03-24T15:00:00+08:00",
            end_at="2026-03-24T16:00:00+08:00",
            source_app="Messages",
            page_url=None,
        ),
        raw_model_response={"intent": "schedule"},
    )

    assert repo.get_todo_entry(todo_id)["title"] == "Reply to message"
    assert repo.get_reference_entry(reference_id)["title"] == "Interesting article"
    assert repo.get_schedule_entry(schedule_id)["title"] == "Dentist appointment"
    assert len(repo.list_todo_entries()) == 1
    assert len(repo.list_reference_entries()) == 1
    assert len(repo.list_schedule_entries()) == 1


def test_searches_ledger_entries_by_filters_and_sort(tmp_path):
    db_path = tmp_path / "ledger.db"
    init_db(db_path)
    repo = LedgerRepository(db_path)

    repo.create_entry(
        normalized=NormalizedLedgerEntry(
            merchant="Coffee Bean",
            currency="CNY",
            original_amount=Decimal("30.00"),
            discount_amount=Decimal("5.00"),
            actual_amount=Decimal("25.00"),
            category="food",
            occurred_at="2026-03-25T08:30:00+08:00",
        ),
        intent="bookkeeping",
        source_image_path="uploads/coffee.jpg",
        raw_model_response={"intent": "bookkeeping"},
    )
    repo.create_entry(
        normalized=NormalizedLedgerEntry(
            merchant="DiDi",
            currency="CNY",
            original_amount=Decimal("60.00"),
            discount_amount=Decimal("0.00"),
            actual_amount=Decimal("60.00"),
            category="transport",
            occurred_at="2026-03-26T10:00:00+08:00",
        ),
        intent="bookkeeping",
        source_image_path="uploads/didi.jpg",
        raw_model_response={"intent": "bookkeeping"},
    )

    items = repo.search_entries(
        query="di",
        amount_min=50,
        date_from="2026-03-26",
        sort_by="actual_amount",
        sort_order="desc",
        limit=10,
    )

    assert len(items) == 1
    assert items[0]["merchant"] == "DiDi"


def test_returns_ledger_detail_with_pretty_raw_model_response(tmp_path):
    db_path = tmp_path / "ledger.db"
    init_db(db_path)
    repo = LedgerRepository(db_path)

    entry_id = repo.create_entry(
        normalized=NormalizedLedgerEntry(
            merchant="Bakery",
            currency="CNY",
            original_amount=Decimal("18.00"),
            discount_amount=Decimal("3.00"),
            actual_amount=Decimal("15.00"),
            category="food",
            occurred_at="2026-03-24T09:00:00+08:00",
        ),
        intent="bookkeeping",
        source_image_path="uploads/bakery.jpg",
        raw_model_response={"intent": "bookkeeping", "merchant": "Bakery"},
    )

    item = repo.get_entry_detail(entry_id)

    assert item is not None
    assert item["effective_occurred_at"] == "2026-03-24T09:00:00+08:00"
    assert '"merchant": "Bakery"' in item["raw_model_response_json"]
