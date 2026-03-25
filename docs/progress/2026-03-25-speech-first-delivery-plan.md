# 2026-03-25 Delivery Plan

## Objective

Move the project from screenshot-only MVP behavior toward a production-ready speech-first assistant workflow.

## Plan Status

- [x] Inspect current backend, iOS payload models, and docs structure
- [x] Implement `speech_text` and `speech_confidence` through intake, ranking, extraction, and review persistence
- [x] Enforce speech-first intent resolution when speech is explicit and valid
- [x] Update shared iOS models and request payload support for speech metadata
- [x] Add or update backend tests for speech-aware behavior
- [x] Add PRD, architecture, and technical design documents
- [ ] Add native iOS speech capture UI
- [ ] Add production metrics and monitoring
- [ ] Replace keyword-based speech override with a stronger command parser
