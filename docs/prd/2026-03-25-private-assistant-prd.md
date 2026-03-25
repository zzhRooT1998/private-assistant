# Private Assistant PRD

## Document Status

- Version: `v1`
- Date: `2026-03-25`
- Scope: production-oriented screenshot + speech mobile assistant

## Product Summary

Private Assistant is an iPhone-first personal agent that turns an explicit user trigger into a structured task. The trigger captures the current screen, optionally captures a short spoken command, sends both to the backend, infers the user's intent, and either executes the action directly or asks the user to confirm among the top intent candidates.

The product is no longer scoped as an MVP. The target is a deployable personal assistant workflow that is reliable enough for daily use on bookkeeping, todo capture, schedule capture, and save-for-later flows.

## Product Goals

1. Let the user trigger capture from anywhere on iPhone with low friction.
2. Prefer explicit spoken commands over ambiguous screen context.
3. Execute supported actions automatically when confidence is high and required fields are available.
4. Use HITL confirmation when intent ambiguity remains after multimodal analysis.
5. Keep the system inspectable through saved records, ranked intents, and review queues.

## Non-Goals

- Fully autonomous actions inside third-party apps
- Fully automated payments or purchases
- Multi-user collaboration
- Cloud account system in the current phase
- Cross-platform desktop parity in the current phase

## Target Users

- Individual users who want fast capture-to-action flows
- Users who frequently convert screenshots into bookkeeping, reminders, or saved references
- Users who are willing to confirm ambiguous decisions but do not want to fill forms manually

## Core Use Cases

### 1. Screenshot + Speech Bookkeeping

The user captures a payment screen and says "帮我记这笔账". The system should treat speech as the primary intent signal, extract merchant and amount from the screenshot, and save a bookkeeping entry.

### 2. Screenshot + Speech Reminder

The user captures a product or message and says "提醒我今晚处理这个". The system should classify the intent as schedule or todo based on the spoken command and available time expression.

### 3. Screenshot-Only Capture

The user captures a receipt or payment page without speaking. The system should infer the likely intent from the visual context and execute if confidence is high.

### 4. Ambiguous Multi-Intent Capture

The user captures content that could reasonably map to multiple intents. The system should return the top three ranked intents and ask the user to choose or override with a custom intent.

## Product Principles

- Speech-first when speech is explicit and valid
- Screenshot as contextual evidence, not the sole authority
- Transparent automation through ranked intents and confirmation reasons
- Reliable fallbacks over hidden failures
- Fast enough for repeated daily use

## Functional Requirements

### Capture and Intake

- The system must accept image capture, typed text, page URL, source metadata, and optional speech transcript.
- The system must accept `speech_confidence` when provided by the client.
- The system must reject empty intake payloads.

### Intent Resolution

- The system must support `bookkeeping`, `todo`, `reference`, `schedule`, and `unknown`.
- When speech is explicit and valid, the system must prioritize the speech-derived intent over conflicting screenshot cues.
- When speech is weak or ambiguous, the system must fall back to multimodal ranking and HITL thresholds.

### HITL

- The system must store pending reviews with the original capture context and ranked intents.
- The client must be able to fetch pending reviews.
- The user must be able to pick one of the top ranked intents or provide a supported custom intent override.

### Execution

- The system must execute supported handlers when required fields are available.
- The system must not auto-execute unsupported or under-specified intents.
- The system must return structured output for both executed and non-executed captures.

### Observability

- The system must preserve raw model outputs in persistence layers where applicable.
- The system must preserve ranked intents and review reasons for pending HITL items.
- The client must surface user-visible feedback for shortcut send success and failure.

## Non-Functional Requirements

- Local development should run on a single FastAPI process and SQLite.
- Core backend tests must run in CI-style local execution.
- iOS client shared models must stay in sync with backend response contracts.
- The product must remain operable even when a capture cannot be auto-executed.

## Success Metrics

- High auto-execution rate for explicit screenshot + speech commands
- Low false-positive execution rate
- Low shortcut failure invisibility rate due to user-facing notifications
- Short confirmation loop for ambiguous captures

## Risks

- Speech recognition quality varies by noise and language context
- Third-party app screens may provide insufficient evidence for extraction
- Background shortcut execution can be interrupted by iOS runtime limits
- Provider output quality may drift across multimodal models

## Release Phases

### Phase 1

- Speech-first backend intent resolution
- HITL review queue
- iOS screenshot shortcut flow

### Phase 2

- Native in-app speech capture UI
- More explicit user review states and retry flows
- Structured analytics and audit views

### Phase 3

- Additional action handlers
- Optional push delivery and remote completion signals
