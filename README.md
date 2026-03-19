# private-assistant

Minimal life-agent MVP that accepts receipt images, infers bookkeeping intent with an OpenAI-compatible multimodal model, stores normalized ledger entries in SQLite, and renders a small server-side UI.

## Features

- Receipt image upload through a browser form or API
- Multimodal parsing behind an OpenAI-compatible service layer
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
  Accepts `multipart/form-data` with an `image` field.
- `GET /api/ledger`
  Returns recent stored entries.
- `GET /api/ledger/{id}`
  Returns one stored entry.

## Tests

Run:

```bash
python -m pytest
```
