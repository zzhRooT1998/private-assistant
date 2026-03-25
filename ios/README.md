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

The default server URL is `https://b308-112-10-191-85.ngrok-free.app`.

- Replace it with your current tunnel or your Mac's LAN IP if the default tunnel changes.

## Shortcut Setup

Use one of these two shortcut flows on iPhone:

Stable screenshot-only flow:

1. Add `Take Screenshot`
2. Add `Send Screenshot Only`
3. Pass the screenshot output into the `Screenshot` parameter
4. Bind this shortcut to Back Tap if you want the most reliable trigger

Screenshot plus system dictation flow:

1. Add `Take Screenshot`
2. Add `Dictate Text`
3. Add `Send To Private Assistant`
4. Pass the screenshot output into the `Screenshot` parameter
5. Pass the `Dictate Text` output into the `Spoken Command` parameter
6. Enable `Show When Run` if you want the dialog confirmation

The second flow keeps the user in Shortcuts system UI for voice input instead of opening the app just to record audio. If the iPhone is in a phone call or dictation is otherwise unavailable, use the screenshot-only shortcut so capture still works.

## Important Gaps

- The scaffold is currently configured to avoid `App Groups`, so it works with a Personal Team account more easily. That means the main app and share extension do not share the backend URL automatically.
- The share extension now loads a draft and lets the user confirm before upload, but it still needs visual polish.
- This scaffold was generated without full Xcode validation in the current environment, so run one compile pass in Xcode before adding product polish.
