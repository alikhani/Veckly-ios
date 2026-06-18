# Staging Plan - 2026-06

Status: paused
Updated: 2026-06-18

## Goal

Use a production-shaped auth flow for `Veckly-ios` while keeping simulator work
fast and isolated from live production households.

Build split:

- `Debug` / simulator -> staging
- `Release` / TestFlight -> production

## Implemented in this branch

- Added `xcconfig`-based environment wiring
- Added explicit app environments:
  - `staging`
  - `production`
- Added debug-only dev login affordance
- Added dev-login session persistence
- Added UI test hooks:
  - `-UIReset`
  - `-UITestUserId=<uuid>`
- Added local override mechanism:
  - `Config/DeveloperOverrides.xcconfig`

## Current local workflow

Committed defaults stay safe:

- production values are committed for `Release`
- staging defaults are placeholders for `Debug`

Local-only staging values should live in:

- `Config/DeveloperOverrides.xcconfig`

Example file:

- `Config/DeveloperOverrides.example.xcconfig`

Suggested contents:

```xcconfig
VECKLY_STAGING_API_BASE_URL = https://<your-veckly-backend-preview-url>.vercel.app
VECKLY_STAGING_SUPABASE_URL = https://<your-staging-project-ref>.supabase.co
VECKLY_STAGING_SUPABASE_ANON_KEY = <your-staging-anon-key>
```

## What we learned

- `MealPlanner` preview is not enough to serve as Veckly iOS staging auth
- `MealPlanner` uses Better Auth, while this app now expects Supabase bearer-token
  auth through `Veckly-backend`
- the right long-term shape is real staging Supabase Auth for Veckly

## Next steps

1. Fill local `DeveloperOverrides.xcconfig` with real staging values.
2. Configure `Veckly-backend` preview with:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `ENABLE_DEV_AUTH=true`
   - dev test-user config
3. Verify `Sign in as dev` end-to-end in simulator.
4. Verify session restoration after relaunch.
5. Keep `Release` free from any dev-login affordance.

## Acceptance checklist

- Debug build shows `Sign in as dev`
- tapping it enters the signed-in app
- relaunch restores the session
- Release build hides the dev-login button
- simulator-created data stays out of production
