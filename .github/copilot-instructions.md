# Project Guidelines

## Architecture
- Repo is split into `backend/` (Node.js + Express + MongoDB + Socket.IO) and `moodiary/` (Flutter app).
- Backend entry points: `backend/server.js` for HTTP API and `backend/socket.js` for realtime events.
- Flutter app entry point: `moodiary/lib/main.dart`; shared app behavior is primarily in `moodiary/lib/services/`.
- Keep API and realtime contracts aligned: route payload shapes and socket event names must remain backward-compatible unless all callers are updated in the same change.

## Build And Test
- Backend setup and run:
  - `cd backend`
  - `npm install`
  - `npm run dev` (preferred while developing)
- Flutter setup and run:
  - `cd moodiary`
  - `flutter pub get`
  - `flutter analyze`
  - `flutter run`
- If a Flutter or backend change can affect behavior, validate with at least one runnable command from the relevant side before finishing.

## Conventions
- Follow existing folder boundaries:
  - backend routes in `backend/routes/`, auth checks in `backend/middleware/auth.js`, shared backend helpers in `backend/utils/`.
  - Flutter screens in `moodiary/lib/screens/`, reusable UI in `moodiary/lib/widgets/`, cross-screen logic in `moodiary/lib/services/`.
- Prefer extending existing service singletons in Flutter before introducing a new state-management pattern.
- Use existing error-response shape conventions (`{ error: "..." }` from backend) and map them to user-friendly UI messages.
- Keep naming and API surface consistent with adjacent files instead of introducing new style variants.

## Performance And Reliability Gates
- Prioritize smooth UX: avoid adding synchronous heavy work on Flutter UI paths; move repeated or expensive work out of build/render flows.
- Avoid redundant network calls from multiple tabs/screens for the same data in a single interaction path.
- For new list/history endpoints, require pagination or bounded responses by default.
- Preserve realtime stability: keep socket reconnect and auth-token handling robust when app resumes or network changes.
- Do not hardcode environment-specific endpoints in new code; keep URL/config behavior consistent with current environment strategy.

## Cross-Tab Consistency Requirements
- Changes to shared entities (user profile, friendship state, notifications, mood/journal summaries) must stay consistent across all relevant tabs/screens.
- When modifying shared data contracts, update all impacted tabs in the same task (for example: home, profile, friends, notifications).
- Reuse shared theme tokens and common widgets so visual behavior stays consistent across tabs.
- Keep loading, empty, and error states aligned across tabs for the same feature family.

## Documentation Links
- See `moodiary/README.md` for environment setup and auth/password-reset flow details.
- See `moodiary/docs/mbti_methodology.md` for MBTI scoring methodology.