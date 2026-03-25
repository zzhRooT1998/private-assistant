# Private Assistant Architecture

## Overview

Private Assistant is a single-repo system with two deployable surfaces:

1. A Python backend built on FastAPI, SQLite, LangChain, and LangGraph
2. An iOS client built with SwiftUI, App Intents, and a Share Extension

The production architecture is optimized around screenshot-triggered capture, optional speech guidance, and human confirmation for ambiguous intent classification.

## System Context

### Client Layer

- `PrivateAssistantApp`
  Main SwiftUI application for capture, settings, activity views, ledger views, and pending HITL reviews
- `App Shortcut / App Intent`
  Trigger entry for screenshot submission from Shortcuts or Back Tap
- `Share Extension`
  Entry for user-driven sharing of screenshots, links, and text

### Backend Layer

- `FastAPI API`
  Receives intake payloads and exposes stored record endpoints
- `IntentWorkflowService`
  LangGraph orchestration for ranking, confirmation decisions, and extraction
- `VisionIntentService`
  LangChain prompt construction and OpenAI-compatible multimodal calls
- `Normalization / Execution`
  Intent-specific validation and persistence
- `SQLite Repository`
  Durable storage for executed records and pending reviews

## High-Level Flow

1. iPhone captures a screenshot and optionally speech transcript.
2. Client submits `multipart/form-data` to `POST /agent/life/mobile-intake`.
3. Backend stores the image locally when present.
4. `IntentWorkflowService` ranks top intent candidates.
5. If speech contains an explicit valid command, the workflow biases or forces the speech intent.
6. If ambiguity remains, backend stores an `intent_review` and returns `requires_confirmation=true`.
7. If confidence is sufficient, backend extracts intent-specific fields and executes the handler.
8. iOS app refreshes activity and pending review queues.

## Architecture Decisions

### 1. Speech Is a First-Class Input

Speech is modeled separately from `text_input`.

- `text_input` represents passive or shared textual context
- `speech_text` represents active user instruction

This distinction is necessary because the backend needs different semantics:

- shared text is evidence
- speech is intent guidance

### 2. Speech-First Resolution Rule

When speech is explicit and valid, speech wins over screenshot context.

This is implemented before final extraction so that:

- the chosen intent is stable
- the screenshot remains available for entity extraction
- HITL is bypassed for explicit user commands

### 3. Two-Stage Intent Processing

The backend separates:

1. ranking
2. extraction

This prevents the system from mixing extraction schemas across incompatible intents and makes HITL possible before execution.

### 4. SQLite for Review and Execution Records

SQLite remains acceptable at this stage because:

- workload is single-user and low-volume
- review history and execution records are relational and simple
- operational complexity stays low

## Component Diagram

### iOS

- `PrivateAssistantShared`
  Shared API models and HTTP client
- `PrivateAssistantApp`
  SwiftUI views and application state
- `PrivateAssistantShareExtension`
  share-sheet ingestion

### Python Backend

- `app/main.py`
  route definitions and intake orchestration
- `app/services/intent_graph.py`
  workflow graph and HITL decision rules
- `app/services/vision.py`
  prompt generation, multimodal requests, speech-priority rules
- `app/services/intents.py`
  todo / reference / schedule normalization
- `app/services/bookkeeping.py`
  bookkeeping normalization
- `app/repository.py`
  persistence boundary
- `app/db.py`
  schema initialization and migrations

## Data Stores

### Uploaded Files

- Stored in `uploads/`
- Used as input evidence for multimodal analysis

### SQLite Tables

- `ledger_entries`
- `todo_entries`
- `reference_entries`
- `schedule_entries`
- `intent_reviews`

`intent_reviews` stores the original context needed for delayed confirmation, including speech fields.

## API Surface

### Intake

- `POST /agent/life/intake`
- `POST /agent/life/mobile-intake`

### Confirmation

- `POST /agent/life/mobile-intake/{review_id}/confirm`

### Query

- `GET /api/ledger`
- `GET /api/todos`
- `GET /api/references`
- `GET /api/schedules`
- `GET /api/intent-reviews`

## Failure Handling

- Provider failure returns `502`
- Invalid payload returns `400`
- Missing executable fields returns `200` with non-executed intent result
- Ambiguity returns `200` with pending confirmation payload

## Operational Notes

- The backend currently assumes a single-process deployment model.
- The iOS shortcut path should never silently fail; local notifications surface background send results.
- The Share Extension still uses a broad activation rule for local development and must be tightened before App Store submission.
