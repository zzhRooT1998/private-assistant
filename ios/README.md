# iOS Scaffold

This folder contains a source-first iOS scaffold for the Private Assistant client:

- `PrivateAssistantApp/`: SwiftUI app with manual capture, activity view, ledger view, settings, and App Intents
- `PrivateAssistantShared/`: shared models, config store, and API client used by the app and share extension
- `PrivateAssistantShareExtension/`: share extension that uploads images, links, or text from the iOS share sheet
- `project.yml`: XcodeGen spec for generating an `.xcodeproj`

## What It Covers

- Manual iPhone-side testing against `POST /agent/life/mobile-intake`
- App Shortcut entry via `SendToPrivateAssistantIntent`
- Share Extension entry for screenshots, images, links, and plain text
- In-app views for recent todos, references, schedules, and bookkeeping entries
- Local `UserDefaults` storage for the backend base URL

## Before Opening In Xcode

1. Install full Xcode and switch the active developer directory to it.
2. Install XcodeGen.
3. Update bundle IDs in:
   - `project.yml`

## Generate The Project

```bash
cd ios
xcodegen generate
open PrivateAssistantMobile.xcodeproj
```

## Backend URL

The default server URL is `http://127.0.0.1:8000`.

- Keep it for the iOS Simulator.
- Replace it with your Mac's LAN IP when testing on a physical iPhone.

## Important Gaps

- The scaffold is currently configured to avoid `App Groups`, so it works with a Personal Team account more easily. That means the main app and share extension do not share the backend URL automatically.
- The share extension now loads a draft and lets the user confirm before upload, but it still needs visual polish.
- This scaffold was generated without full Xcode validation in the current environment, so run one compile pass in Xcode before adding product polish.
