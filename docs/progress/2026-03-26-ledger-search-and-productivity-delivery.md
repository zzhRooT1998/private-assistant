# 2026-03-26 Ledger Search And Productivity Delivery

## Scope

This delivery batch turned the bookkeeping area into a more usable product surface and finished the native execution hooks for saved productivity items on iPhone.

## Plan

- [x] Extend backend ledger APIs to support advanced search and ledger detail retrieval
- [x] Add iPhone ledger filtering, detail view, and search state handling
- [x] Add native execution actions for todos and schedules into Reminders, Calendar, and AlarmKit
- [x] Run backend tests and iOS simulator/device builds
- [x] Update repository documentation and push a coherent delivery batch

## Delivered

### Backend

- `GET /api/ledger` now supports:
  - free-text keyword search
  - category filtering
  - amount min and max filters
  - date range filtering
  - server-side sort selection and sort order
- `GET /api/ledger/filters` now exposes filter metadata for the iPhone UI.
- `GET /api/ledger/{id}` now returns a richer detail payload, including:
  - effective occurred timestamp
  - pretty-printed raw model response JSON

### iPhone client

- The `Ledger` tab now supports:
  - search by keyword
  - filter sheet with category, amount, date, and sort controls
  - visible total summaries for the current result set
  - detail sheet for each entry
- The detail sheet shows:
  - amount breakdown
  - merchant/category/currency metadata
  - event timestamps
  - raw model response for inspection and debugging

### Native productivity actions

- `todo` entries can be exported into Apple Reminders.
- `schedule` entries can be exported into Apple Calendar.
- Future todo and schedule items can be turned into system alarms on `iOS 26.1+` through AlarmKit.

## Verification

- `./.venv/bin/python -m pytest -q`
  - Result: `36 passed, 1 warning`
- `xcodebuild -project ios/PrivateAssistantMobile.xcodeproj -scheme PrivateAssistantApp -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
  - Result: `BUILD SUCCEEDED`
- `xcodebuild -project ios/PrivateAssistantMobile.xcodeproj -scheme PrivateAssistantApp -sdk iphoneos CODE_SIGNING_ALLOWED=NO build`
  - Result: `BUILD SUCCEEDED`

## Notes

- The Python warning comes from `langchain_core` using Pydantic v1 compatibility paths under Python `3.14`. It does not block the current delivery, but the stack should eventually move to a Python version and dependency combination officially supported by LangChain.
- The iPhone productivity actions are explicit user actions from the app. They are not background auto-sync jobs.
