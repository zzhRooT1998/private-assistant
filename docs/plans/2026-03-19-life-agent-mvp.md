# Life Agent MVP Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a minimal life-agent web app that accepts a bill image, uses an OpenAI-compatible multimodal model to detect bookkeeping intent, extracts payable receipt data, stores the entry in SQLite, and shows the result in a simple UI.

**Architecture:** Use a single FastAPI app with server-rendered HTML. Keep persistence in SQLite via the Python standard library, keep uploads on local disk, and isolate model access behind a small service that returns typed receipt extraction data. Only one executable intent exists in the MVP: bookkeeping.

**Tech Stack:** Python 3.13, FastAPI, Jinja2, OpenAI Python SDK, SQLite, pytest, httpx

---

### Task 1: Bootstrap project structure and dependencies

**Files:**
- Create: `pyproject.toml`
- Create: `.gitignore`
- Create: `.env.example`
- Create: `app/__init__.py`
- Create: `app/services/__init__.py`
- Create: `app/templates/.gitkeep`
- Create: `app/static/.gitkeep`
- Create: `tests/__init__.py`

**Step 1: Write the failing test**

```python
from pathlib import Path


def test_project_scaffold_exists():
    assert Path("pyproject.toml").exists()
    assert Path("app").is_dir()
    assert Path("tests").is_dir()
```

**Step 2: Run test to verify it fails**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_scaffold.py -v`
Expected: FAIL because the project files do not exist yet

**Step 3: Write minimal implementation**

```toml
[project]
name = "private-assistant"
version = "0.1.0"
dependencies = [
  "fastapi>=0.116.0",
  "uvicorn>=0.35.0",
  "python-multipart>=0.0.9",
  "jinja2>=3.1.4",
  "openai>=1.51.0"
]

[project.optional-dependencies]
dev = ["pytest>=8.3.0", "httpx>=0.28.0"]
```

Create the directories and a basic `.env.example` with:

```env
OPENAI_API_KEY=
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=gpt-4.1-mini
APP_UPLOAD_DIR=uploads
APP_DATABASE_URL=ledger.db
```

**Step 4: Run test to verify it passes**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_scaffold.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add pyproject.toml .gitignore .env.example app tests
git commit -m "chore: bootstrap life agent project"
```

### Task 2: Add bookkeeping domain logic with TDD

**Files:**
- Create: `app/schemas.py`
- Create: `app/services/bookkeeping.py`
- Create: `tests/test_bookkeeping_service.py`

**Step 1: Write the failing test**

```python
from decimal import Decimal

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
```

Add a second test for fallback calculation:

```python
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
```

**Step 2: Run test to verify it fails**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_bookkeeping_service.py -v`
Expected: FAIL because schemas and service do not exist

**Step 3: Write minimal implementation**

```python
from dataclasses import dataclass
from decimal import Decimal


@dataclass
class NormalizedLedgerEntry:
    merchant: str | None
    currency: str | None
    original_amount: Decimal | None
    discount_amount: Decimal
    actual_amount: Decimal
    category: str | None
    occurred_at: str | None
```

Implement `normalize_bookkeeping_entry()` to:

- parse strings into `Decimal`
- default missing discount to `Decimal("0")`
- prefer `actual_amount`
- otherwise compute `original_amount - discount_amount`
- raise `ValueError` when payable amount is missing or negative

**Step 4: Run test to verify it passes**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_bookkeeping_service.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/schemas.py app/services/bookkeeping.py tests/test_bookkeeping_service.py
git commit -m "feat: add bookkeeping normalization"
```

### Task 3: Add SQLite storage and listing behavior

**Files:**
- Create: `app/db.py`
- Create: `app/repository.py`
- Create: `tests/test_repository.py`

**Step 1: Write the failing test**

```python
from app.db import init_db
from app.repository import LedgerRepository
from app.services.bookkeeping import NormalizedLedgerEntry


def test_inserts_and_lists_ledger_entries(tmp_path):
    db_path = tmp_path / "ledger.db"
    init_db(db_path)
    repo = LedgerRepository(db_path)

    entry_id = repo.create_entry(
        normalized=NormalizedLedgerEntry(
            merchant="Coffee",
            currency="CNY",
            original_amount=None,
            discount_amount=0,
            actual_amount=18,
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
```

**Step 2: Run test to verify it fails**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_repository.py -v`
Expected: FAIL because database modules do not exist

**Step 3: Write minimal implementation**

Create a table initializer and repository methods:

```sql
CREATE TABLE IF NOT EXISTS ledger_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  merchant TEXT,
  currency TEXT,
  original_amount TEXT,
  discount_amount TEXT NOT NULL,
  actual_amount TEXT NOT NULL,
  category TEXT,
  occurred_at TEXT,
  intent TEXT NOT NULL,
  source_image_path TEXT NOT NULL,
  raw_model_response TEXT NOT NULL,
  created_at TEXT NOT NULL
)
```

Implement:

- `init_db(db_path)`
- `LedgerRepository.create_entry(...)`
- `LedgerRepository.list_entries(limit)`
- `LedgerRepository.get_entry(entry_id)`

**Step 4: Run test to verify it passes**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_repository.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/db.py app/repository.py tests/test_repository.py
git commit -m "feat: add sqlite ledger repository"
```

### Task 4: Add OpenAI-compatible vision client contract

**Files:**
- Create: `app/config.py`
- Create: `app/services/vision.py`
- Create: `tests/test_vision_service.py`

**Step 1: Write the failing test**

```python
from app.services.vision import build_receipt_prompt


def test_prompt_requires_bookkeeping_or_unknown():
    prompt = build_receipt_prompt()
    assert "bookkeeping" in prompt
    assert "unknown" in prompt
    assert "actual_amount" in prompt
```

**Step 2: Run test to verify it fails**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_vision_service.py -v`
Expected: FAIL because the vision module does not exist

**Step 3: Write minimal implementation**

Create:

- `Settings` loader for `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `OPENAI_MODEL`, `APP_UPLOAD_DIR`, `APP_DATABASE_URL`
- `build_receipt_prompt()` helper that requests strict JSON
- `VisionIntentService` with a `parse_image(image_bytes, content_type)` method

The model response JSON contract should look like:

```json
{
  "intent": "bookkeeping | unknown",
  "confidence": 0.0,
  "merchant": null,
  "currency": null,
  "original_amount": null,
  "discount_amount": null,
  "actual_amount": null,
  "category_guess": null,
  "occurred_at": null
}
```

**Step 4: Run test to verify it passes**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_vision_service.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/config.py app/services/vision.py tests/test_vision_service.py
git commit -m "feat: add multimodal vision parsing service"
```

### Task 5: Add the life-agent intake API with mocked model tests first

**Files:**
- Create: `app/main.py`
- Create: `tests/conftest.py`
- Create: `tests/test_api_intake.py`

**Step 1: Write the failing test**

```python
from io import BytesIO


def test_intake_creates_ledger_entry(client, monkeypatch):
    async def fake_parse_image(*args, **kwargs):
        return {
            "intent": "bookkeeping",
            "confidence": 0.95,
            "merchant": "Bakery",
            "currency": "CNY",
            "original_amount": "25.00",
            "discount_amount": "5.00",
            "actual_amount": "20.00",
            "category_guess": "food",
            "occurred_at": None,
        }

    monkeypatch.setattr("app.main.parse_uploaded_image", fake_parse_image)

    response = client.post(
        "/agent/life/intake",
        files={"image": ("receipt.jpg", BytesIO(b"fake-image"), "image/jpeg")},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["intent"] == "bookkeeping"
    assert payload["ledger_entry"]["actual_amount"] == "20.00"
```

**Step 2: Run test to verify it fails**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_api_intake.py -v`
Expected: FAIL because the FastAPI app and endpoint do not exist

**Step 3: Write minimal implementation**

Implement `app/main.py` with:

- FastAPI app factory
- startup database initialization
- `POST /agent/life/intake`
- `GET /api/ledger`
- `GET /api/ledger/{id}`

Keep the orchestration minimal:

```python
if parsed.intent == "unknown":
    return {"intent": "unknown", "ledger_entry": None}

normalized = normalize_bookkeeping_entry(parsed)
entry_id = repository.create_entry(...)
```

**Step 4: Run test to verify it passes**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_api_intake.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/main.py tests/conftest.py tests/test_api_intake.py
git commit -m "feat: add life agent intake api"
```

### Task 6: Add minimal UI for upload and ledger display

**Files:**
- Create: `app/templates/index.html`
- Create: `app/static/styles.css`
- Create: `tests/test_ui.py`

**Step 1: Write the failing test**

```python
def test_home_page_renders_upload_form(client):
    response = client.get("/")
    assert response.status_code == 200
    assert "生活记账 Agent" in response.text
    assert "最近记账" in response.text
```

**Step 2: Run test to verify it fails**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_ui.py -v`
Expected: FAIL because no home page exists yet

**Step 3: Write minimal implementation**

Add:

- `GET /` route rendering `index.html`
- a simple upload form posting to `/agent/life/intake`
- a result area for latest parsed receipt
- a ledger table showing merchant, actual amount, discount, category, created time
- a tiny stylesheet for readable layout

**Step 4: Run test to verify it passes**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_ui.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add app/templates/index.html app/static/styles.css tests/test_ui.py
git commit -m "feat: add minimal ledger ui"
```

### Task 7: Add README and final verification

**Files:**
- Create: `README.md`

**Step 1: Write the failing test**

```python
from pathlib import Path


def test_readme_mentions_required_env_vars():
    text = Path("README.md").read_text(encoding="utf-8")
    assert "OPENAI_API_KEY" in text
    assert "OPENAI_BASE_URL" in text
    assert "OPENAI_MODEL" in text
```

**Step 2: Run test to verify it fails**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_readme.py -v`
Expected: FAIL because README does not exist yet

**Step 3: Write minimal implementation**

Document:

- what the MVP does
- how to install dependencies
- how to set environment variables
- how to run `uvicorn app.main:app --reload`
- how to open the UI
- how to run the test suite

**Step 4: Run test to verify it passes**

Run: `.\.venv\Scripts\python.exe -m pytest tests/test_readme.py -v`
Expected: PASS

Then run the full suite:

Run: `.\.venv\Scripts\python.exe -m pytest -q`
Expected: all tests PASS

**Step 5: Commit**

```bash
git add README.md tests/test_readme.py
git commit -m "docs: add setup and usage guide"
```

### Task 8: Manual verification checklist

**Files:**
- Modify: `README.md`

**Step 1: Write the verification checklist**

Add a short section:

```markdown
## Manual Verification

1. Start the app.
2. Open the home page.
3. Upload a receipt image.
4. Confirm the API returns `intent=bookkeeping` for a valid receipt.
5. Confirm the entry appears in the ledger list with the actual payable amount.
```

**Step 2: Run the app locally**

Run: `.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload`
Expected: server starts on `http://127.0.0.1:8000`

**Step 3: Verify the browser flow**

Run these checks manually:

- load `http://127.0.0.1:8000`
- upload a receipt image
- confirm the parsed fields appear
- confirm the ledger table refreshes

**Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add manual verification checklist"
```
