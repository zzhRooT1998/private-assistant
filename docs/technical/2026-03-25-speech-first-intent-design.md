# Speech-First Intent Technical Design

## Goal

Implement a production-ready multimodal intent pipeline where an explicit spoken command overrides conflicting screenshot context while preserving HITL for truly ambiguous captures.

## Scope

- Add `speech_text` and `speech_confidence` to the intake contract
- Preserve speech context through ranking, extraction, review storage, and response payloads
- Apply explicit speech override before HITL
- Keep backward compatibility with screenshot-only flows

## API Contract

### `POST /agent/life/mobile-intake`

Accepts optional fields:

- `image`
- `text_input`
- `speech_text`
- `speech_confidence`
- `page_url`
- `source_app`
- `source_type`
- `captured_at`

At least one of `image`, `text_input`, `speech_text`, or `page_url` must be present.

## Backend Processing Stages

### 1. Input Normalization

`app/main.py`

- validates presence of at least one primary input
- saves uploaded image when present
- normalizes text fields
- clamps `speech_confidence` into `[0, 1]`

### 2. Intent Ranking

`app/services/intent_graph.py`

- calls `VisionIntentService.rank_intents(...)`
- optionally derives `speech_forced_intent`
- if speech is explicit, moves that intent to the top and disables HITL for that case

### 3. HITL Decision

Current thresholds remain:

- top-two confidence gap `< 0.12` with second confidence `>= 0.35`
- or first confidence `< 0.6` with second confidence `>= 0.25`

Exception:

- if `forced_intent` or `speech_forced_intent` exists, HITL is skipped

### 4. Intent Extraction

`app/services/vision.py`

- builds a strict JSON prompt for `ScreenIntentResult`
- injects spoken command into prompt context as the primary intent signal
- keeps screenshot as evidence for field extraction

### 5. Execution

`app/main.py::_execute_intent`

- normalizes extracted output
- stores record if required fields exist
- otherwise returns a successful non-executed result

## Speech Override Logic

### Explicit Speech Detection

Speech is considered explicit when:

- `speech_text` is non-empty
- `speech_confidence >= 0.55` when provided
- keywords indicate a clear intent

Initial keyword families:

- `bookkeeping`
  `记账`, `记这笔`, `报销`, `expense`, `receipt`, `log this`
- `todo`
  `待办`, `记得`, `稍后处理`, `later`, `follow up`
- `reference`
  `收藏`, `保存这个`, `稍后看`, `save this`, `bookmark`
- `schedule`
  `提醒我`, `日程`, `安排`, `预约`, `开会`, `schedule`, `remind`

Rules:

- no match: no speech override
- tied top score: no speech override
- explicit speech match: speech intent becomes primary

## Prompt Design

### Ranking Prompt

Explicit instruction:

- valid spoken command outweighs conflicting screenshot context

### Extraction Prompt

Explicit instruction:

- treat speech as intent authority
- treat screenshot as grounding and extraction evidence

## Persistence Changes

### `intent_reviews`

Added columns:

- `speech_text`
- `speech_confidence`

This allows delayed confirmation to preserve the original spoken instruction.

## Client Contract

`ios/PrivateAssistantShared`

- `MobileIntakePayload` now supports `speechText` and `speechConfidence`
- shared response models now decode speech fields in analyses and reviews

## Compatibility

- Existing screenshot-only clients continue to work
- Existing review rows remain valid because speech columns are nullable
- Legacy mocks without new speech methods are tolerated in the workflow layer via compatibility fallbacks

## Tests

Coverage added or updated for:

- speech-aware prompt context
- speech-only intake acceptance
- explicit speech override bypassing HITL
- backward compatibility for older mock vision services

## Follow-Up Work

1. Add native iOS speech capture and speech recognition UI
2. Replace keyword override with a more formal command parser or small classifier
3. Add analytics on override rate, HITL rate, and false-positive execution rate
