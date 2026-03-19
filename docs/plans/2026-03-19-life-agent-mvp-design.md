# Life Agent MVP Design

## Goal

Build a minimal life-agent service that accepts an uploaded image, uses an OpenAI-compatible multimodal model to infer user intent, and when the image is a bill or receipt, extracts the payable amount after discounts and stores it in a simple bookkeeping system. The MVP also includes a minimal web UI to upload images and view recorded ledger entries.

## Scope

### In Scope

- A unified life-agent intake endpoint for image uploads
- Multimodal intent classification with OpenAI-compatible API settings
- Receipt parsing for merchant, currency, original amount, discount amount, actual amount, category guess, and occurred time
- Bookkeeping persistence in SQLite
- A minimal browser UI to upload an image and display recent ledger entries
- Basic documentation for setup, environment variables, and local run steps

### Out of Scope

- User accounts and authentication
- Manual edit, delete, or approval workflows
- Multiple executable intents beyond bookkeeping
- Object storage or cloud database integrations
- Advanced categorization, analytics, or reporting
- Background jobs and async task orchestration

## Architecture

The MVP is a single FastAPI application with five minimal layers:

1. `Life Agent API`
   Receives image uploads through a single intake endpoint and returns structured results.

2. `Vision Intent Service`
   Calls an OpenAI-compatible multimodal model and requests a constrained JSON response. The model decides whether the image is a bookkeeping candidate and extracts receipt fields.

3. `Bookkeeping Service`
   Validates extracted fields and computes the payable amount with a strict rule:
   - Use `actual_amount` if the model extracted it reliably.
   - Otherwise compute `original_amount - discount_amount`.
   - Default missing discount to `0`.
   - Reject negative payable amounts.

4. `SQLite Ledger`
   Stores the normalized ledger entry and the raw model response.

5. `Minimal UI`
   A simple server-rendered page to upload an image and list the latest bookkeeping entries.

## Data Flow

1. User uploads an image through the UI or directly to `POST /agent/life/intake`.
2. The API validates the image and stores it in a local `uploads/` directory.
3. The Vision Intent Service sends the image and extraction instructions to the multimodal model.
4. If the model returns `intent=bookkeeping`, the Bookkeeping Service normalizes fields and computes the final payable amount.
5. The ledger entry is inserted into SQLite.
6. The API returns the detected intent, parsed receipt data, and the stored ledger entry.
7. The UI refreshes the latest entries from the ledger listing endpoint.

## API Design

### `POST /agent/life/intake`

Consumes `multipart/form-data` with one `image` field.

Response shape:

```json
{
  "intent": "bookkeeping",
  "confidence": 0.93,
  "parsed_receipt": {
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
  "message": "Bookkeeping entry created."
}
```

### `GET /api/ledger`

Returns the latest ledger entries for the UI.

### `GET /api/ledger/{id}`

Returns the full stored entry with raw parsed fields.

## Data Model

One table is enough for the MVP.

### `ledger_entries`

- `id` integer primary key
- `merchant` text
- `currency` text
- `original_amount` text
- `discount_amount` text
- `actual_amount` text
- `category` text
- `occurred_at` text
- `intent` text
- `source_image_path` text
- `raw_model_response` text
- `created_at` text

Amounts are stored as strings in the database layer after Decimal normalization to avoid float drift and keep serialization straightforward for the MVP.

## Model Contract

The multimodal prompt should force JSON output with the following keys:

```json
{
  "intent": "bookkeeping | unknown",
  "confidence": 0.0,
  "merchant": "string or null",
  "currency": "string or null",
  "original_amount": "string or null",
  "discount_amount": "string or null",
  "actual_amount": "string or null",
  "category_guess": "string or null",
  "occurred_at": "ISO8601 string or null"
}
```

If the image is not clearly a receipt or bill, the model must return `intent=unknown`.

## Business Rules

- Prefer extracted `actual_amount` over computed values.
- If `actual_amount` is missing, compute `original_amount - discount_amount`.
- Treat missing `discount_amount` as zero.
- Reject entries where required monetary fields are missing or payable amount becomes negative.
- Persist the raw model response for debugging and future prompt iteration.

## Error Handling

- `400 Bad Request`
  Missing image or unsupported content type.
- `422 Unprocessable Entity`
  Model response is malformed or insufficient for bookkeeping.
- `502 Bad Gateway`
  Model provider call fails.
- `500 Internal Server Error`
  Local file or database write fails.

For images classified as non-bookkeeping, the API returns a successful response with `intent=unknown` and no created ledger entry.

## UI Design

The UI is intentionally small:

- Top section: image upload form
- Upload result panel: intent, merchant, original amount, discount amount, actual amount
- Ledger table: recent entries ordered by creation time descending

The UI should be server-rendered to keep the MVP small and avoid adding a frontend build system.

## Testing Strategy

### Unit Tests

- Amount normalization and payable amount calculation
- Validation of malformed model outputs
- Ledger insertion behavior

### API Tests

- Upload image and create bookkeeping entry when model returns bookkeeping JSON
- Upload image and return `intent=unknown` without insertion
- Reject malformed uploads

### UI Verification

- Confirm the root page loads
- Confirm the latest ledger data appears after a successful upload

## Configuration

Environment variables:

- `OPENAI_API_KEY`
- `OPENAI_BASE_URL`
- `OPENAI_MODEL`
- `APP_UPLOAD_DIR`
- `APP_DATABASE_URL`

The code uses the OpenAI Python SDK only, so the backend remains compatible with OpenAI and Qwen deployments that expose an OpenAI-compatible endpoint.

## Documentation Deliverables

- Setup and run instructions in `README.md`
- Example environment file in `.env.example`
- This design doc
- A task-by-task implementation plan
