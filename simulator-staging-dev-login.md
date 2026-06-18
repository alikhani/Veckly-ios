# Simulator / Staging / Dev Login

Status: active
Updated: 2026-06-18

## Build behavior

- `Debug` builds resolve to `staging`
- `Release` builds resolve to `production`
- `Sign in as dev` is shown only when `VECKLY_ENABLE_DEV_LOGIN=YES`

The app now reads its environment from Info.plist-backed build settings, not from
runtime hardcoded production fallbacks.

## Build settings

Configured in:

- `/Users/nima/Documents/dev/Veckly/Veckly-ios/Config/Base.xcconfig`
- `/Users/nima/Documents/dev/Veckly/Veckly-ios/Config/Debug.xcconfig`
- `/Users/nima/Documents/dev/Veckly/Veckly-ios/Config/Release.xcconfig`

Info.plist keys:

- `VECKLY_API_BASE_URL`
- `VECKLY_SUPABASE_URL`
- `VECKLY_SUPABASE_ANON_KEY`
- `VECKLY_ENVIRONMENT`
- `VECKLY_ENABLE_DEV_LOGIN`

## What still needs real values

The current staging values in `Base.xcconfig` are placeholders and must be replaced
with the real staging backend and Supabase values before simulator login can talk to
live staging:

- `VECKLY_STAGING_API_BASE_URL`
- `VECKLY_STAGING_SUPABASE_URL`
- `VECKLY_STAGING_SUPABASE_ANON_KEY`

Recommended during the transition: keep the committed placeholders as-is and add
local values in:

- `/Users/nima/Documents/dev/Veckly/Veckly-ios/Config/DeveloperOverrides.xcconfig`

An example file lives at:

- `/Users/nima/Documents/dev/Veckly/Veckly-ios/Config/DeveloperOverrides.example.xcconfig`

This is also the right place to point Veckly Debug at the shared MealPlanner
Supabase project if we use that as staging before a dedicated Veckly staging
project exists.

## UI test hooks

Debug builds support:

- `-UIReset`
- `-UITestUserId=<uuid>`

The UI tests can also use:

- `VECKLY_UI_TEST_MODE=dev-login`

That path seeds a local signed-in state for deterministic UI coverage without a live
network dependency.

## Expected backend contract

The dev-login button calls:

- `POST /auth/dev-token`

Expected response:

```json
{
  "accessToken": "supabase-access-token",
  "refreshToken": "supabase-refresh-token",
  "userId": "uuid"
}
```

The backend route must only be enabled in staging/non-production environments.

## Manual test checklist

1. Build `Debug` and run in simulator.
2. Confirm `Sign in as dev` is visible on the signed-out screen.
3. Tap it and verify the app enters the signed-in flow.
4. Kill and relaunch the app, then verify the session restores.
5. Build `Release` and confirm the dev-login affordance is absent.
