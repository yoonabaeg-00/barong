# Barong Calendar Integration Checkpoint

> Saved: 2026-06-30
> Scope: Native notch Barong Google Calendar integration

## Current Status

- Native notch Barong is the active app target.
- Google Calendar OAuth is connected on this Mac.
- `.env.local` exists with `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`.
- OAuth token is stored locally at `~/Library/Application Support/barong/google-calendar-token.json`.
- Calendar sync state is stored locally at `~/Library/Application Support/barong/google-calendar-state.json`.
- Landing page download now points to the native macOS notch app ZIP.
- Release ZIP is generated at `public/downloads/barong-notch-macos.zip` and copied into `dist/downloads/barong-notch-macos.zip`.
- The release ZIP includes app OAuth credentials for login, but does not include `.env.local` or any personal Google Calendar token/state files.
- Current synced events:
  - `17:30 테스트중`
  - `17:30 테스트22 · 현석타워-11-회의실1 (50)`

## What Changed

- Added `scripts/calendar-helper.cjs`.
  - Handles Google OAuth login without showing the Electron prototype.
  - Reads Google Calendar events using `calendar.events.readonly`.
  - Writes local state for the native notch app.
  - Extracts meeting room from `event.location`, with fallback to resource attendees.

- Updated `native/BarongNotch/Sources/main.swift`.
  - Native notch island now has a `캘린더 연결` button before login.
  - After connection, the button becomes `인사하기`.
  - Calendar refresh runs automatically every 60 seconds.
  - Calendar refresh also runs immediately when the notch island is opened.
  - Meeting card displays up to 2 upcoming events.
  - Meeting card includes room/location when available.
  - Clicking the meeting card opens the meeting link or Google Calendar event.

- Updated Electron prototype path earlier, but it is no longer the main flow.
  - The user specifically wants the native notch Barong.
  - Do not use `bun run dev:app` for the main calendar UX unless debugging the old prototype.

- Updated `README.md`.
  - Contains Google Calendar setup notes, but the current preferred UX is native notch Barong plus `scripts/calendar-helper.cjs`.

## Commands

Run native notch Barong:

```bash
cd ~/Desktop/해커톤/native/BarongNotch
swift run BarongNotch
```

Manually refresh calendar state:

```bash
cd ~/Desktop/해커톤
node scripts/calendar-helper.cjs list
```

Check connection:

```bash
cd ~/Desktop/해커톤
node scripts/calendar-helper.cjs status
```

Build landing page plus downloadable native app:

```bash
cd ~/Desktop/해커톤
bun run build:release
```

## Verification

Last verified:

```bash
cd ~/Desktop/해커톤/native/BarongNotch
swift build
```

Result: build passed.

```bash
cd ~/Desktop/해커톤
node scripts/calendar-helper.cjs list
```

Result: connected, 2 events returned.

Latest release verification:

```bash
cd ~/Desktop/해커톤
bun run build
npm run lint
codesign --verify --deep --strict --verbose=2 /tmp/barong-dist-check/바롱이.app
```

Result: build passed, lint passed, packaged app signature verified after extracting the ZIP.

## Notes For Next Session

- This folder is not a Git repository, so no commit was created.
- Do not print OAuth secrets in responses.
- If the island shows stale events, run `node scripts/calendar-helper.cjs list`, then reopen the notch island.
- If the island says `연결 중` forever, check for a stuck helper:

```bash
pgrep -fl "calendar-helper|BarongNotch"
```

- The expected UX now is:
  - no upcoming events: no meeting card
  - one upcoming event: one row in meeting card
  - two or more upcoming events: first two rows in meeting card
