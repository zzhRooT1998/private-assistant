# private-assistant

Minimal life-agent MVP that accepts iPhone screenshots, shared text, URLs, and receipt images, infers user intent with an OpenAI-compatible multimodal model, stores normalized bookkeeping entries in SQLite, and renders a small server-side UI.

## Features

- Receipt image upload through a browser form or API
- Generic mobile intake for screenshots, shared text, and URLs
- Multimodal parsing behind an OpenAI-compatible service layer
- Intent routing that can recognize bookkeeping, todo, reference, schedule, or unknown
- Executable handlers for bookkeeping, todo capture, reference saving, and schedule capture
- Strict bookkeeping normalization for discount and payable amount
- SQLite-backed ledger storage with raw model response retention
- Simple HTML UI for upload results and recent entries

## Setup

1. Create a virtual environment and install dependencies.
2. Copy `.env.example` to `.env` and fill in your provider settings.
3. Run the app with `uvicorn app.main:app --reload`.

The app reads `.env` automatically on startup.

Example environment variables:

```env
OPENAI_API_KEY=
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=gpt-4.1-mini
APP_UPLOAD_DIR=uploads
APP_DATABASE_URL=ledger.db
```

## API

- `POST /agent/life/intake`
  Accepts `multipart/form-data` with an `image` field. This keeps the original receipt-upload flow for the web UI and simple clients.
- `POST /agent/life/mobile-intake`
  Accepts `multipart/form-data` with any of:
  - `image`: optional screenshot or shared image
  - `text_input`: optional text extracted from Shortcuts or Share Extension
  - `page_url`: optional URL for the current page
  - `source_app`: optional app name such as `Safari` or `WeChat`
  - `source_type`: optional source type such as `screenshot`, `onscreen`, or `share_extension`
  - `captured_at`: optional ISO8601 timestamp
- `GET /api/ledger`
  Returns recent stored entries.
- `GET /api/ledger/{id}`
  Returns one stored entry.
- `GET /api/todos`
  Returns recent todo entries.
- `GET /api/references`
  Returns recent reference entries.
- `GET /api/schedules`
  Returns recent schedule entries.

### Mobile Intake Example

```bash
curl -X POST http://127.0.0.1:8000/agent/life/mobile-intake \
  -F "image=@/path/to/screenshot.jpg" \
  -F "text_input=Please remind me to reply tonight" \
  -F "page_url=https://example.com/chat/123" \
  -F "source_app=WeChat" \
  -F "source_type=onscreen" \
  -F "captured_at=2026-03-23T20:15:00+08:00"
```

Response shape:

```json
{
  "intent": "bookkeeping",
  "confidence": 0.93,
  "analysis": {
    "intent": "bookkeeping",
    "action": "create_bookkeeping_entry",
    "summary": "Receipt from Sample Cafe.",
    "source_app": "Alipay",
    "source_type": "screenshot",
    "page_url": null,
    "extracted_text": null,
    "merchant": "Sample Cafe",
    "currency": "CNY",
    "original_amount": "42.00",
    "discount_amount": "8.00",
    "actual_amount": "34.00",
    "category_guess": "food",
    "occurred_at": "2026-03-19T12:30:00+08:00"
  },
  "parsed_receipt": {
    "intent": "bookkeeping",
    "action": "create_bookkeeping_entry",
    "summary": "Receipt from Sample Cafe.",
    "source_app": "Alipay",
    "source_type": "screenshot",
    "page_url": null,
    "extracted_text": null,
    "merchant": "Sample Cafe",
    "currency": "CNY",
    "original_amount": "42.00",
    "discount_amount": "8.00",
    "actual_amount": "34.00",
    "category_guess": "food",
    "occurred_at": "2026-03-19T12:30:00+08:00"
  },
  "ledger_entry": {
    "id": 1,
    "merchant": "Sample Cafe",
    "actual_amount": "34.00"
  },
  "todo_entry": null,
  "reference_entry": null,
  "schedule_entry": null,
  "executed_action": "create_bookkeeping_entry",
  "message": "Bookkeeping entry created."
}
```

`parsed_receipt` is kept for backward compatibility with the original receipt-only clients. New iOS clients should read `analysis` first.

## Tests

Run:

```bash
./.venv/bin/python -m pytest
```

## iOS Client Scaffold

An iPhone client scaffold now lives in [`ios/`](./ios):

- `PrivateAssistantApp/`: SwiftUI app
- `PrivateAssistantShared/`: shared models and API client
- `PrivateAssistantShareExtension/`: share extension
- `project.yml`: XcodeGen spec

See [`ios/README.md`](./ios/README.md) for setup steps. The current environment does not have full Xcode enabled, so the scaffold was generated source-first and should be compiled once in Xcode before product work continues.
