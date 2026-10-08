# Veckly-ios

The native iOS app for Veckly, a weekly family dinner planner. It is built with SwiftUI, Swift
Concurrency and Observation, and it talks to [Veckly-backend](../Veckly-backend) through a client
generated from the backend's OpenAPI spec.

- **How the code is organised:** [ARCHITECTURE.md](ARCHITECTURE.md). Read this before adding a screen.
- **Product and design background:** `../MealPlanner/docs/` (vision, user journeys) and `../MealPlanner/DESIGN.md`
  (Hearth Orange `#e4572e`, Georgia display serif, calm/warm palette)

## Setup

Requirements: Xcode 27, iOS 26.5 simulator.

```bash
cp Veckly/DebugTestAccount.Local.swift.example Veckly/DebugTestAccount.Local.swift
open Veckly.xcodeproj        # scheme: Veckly
```

`DebugTestAccount.Local.swift` is gitignored and **required for Debug builds**. Put a real test
account's credentials in it to enable the "Sign in as test user" button. The placeholder values
are fine if you sign in another way.

### Which backend does the app use?

By default it uses **production** (`https://veckly-backend.vercel.app`), including in the simulator.
Point it elsewhere with scheme environment variables:

| Variable | Purpose |
|---|---|
| `VECKLY_API_BASE_URL` | e.g. `http://localhost:3001` for a local backend (`npm run dev` in Veckly-backend) |
| `VECKLY_SUPABASE_URL`, `VECKLY_SUPABASE_ANON_KEY` | a different Supabase project |
| `VECKLY_UI_TEST_MODE=core-reader` | offline seeded data, no network. Used for UI tests and screenshots |
| `VECKLY_UI_TEST_WEEK_SCENARIO` | seeded week variant: `legacyPartial`, `openTonight`, `complete`, … (see `WeekStore.UITestWeekScenario`) |

## Everyday commands

```bash
# unit tests (the commit gate)
xcodebuild test -scheme Veckly -destination 'platform=iOS Simulator,name=<an installed iPhone>' \
  -only-testing:VecklyTests -collect-test-diagnostics never

# after a backend contract change: copy the spec from the backend, then regenerate the client
(cd ../Veckly-backend && npm run openapi:write)
./scripts/generate-openapi-client.sh
```

Never edit `Veckly/Generated/OpenAPI/*`. Those files are regenerated. `Veckly/Generated/VecklyAPIClient.swift`
is the hand-written adapter on top of them.

## Before you commit

- `VecklyTests` is green. Don't use the full `VecklyUITests` suite as a gate; it is slow. For layout
  changes, compare screenshots of the affected states (`VECKLY_UI_TEST_MODE=core-reader`).
- `Localizable.xcstrings`: edit only the keys you touch, validate with `json.load`, and check that
  `git diff --stat` shows only those lines. Don't commit Xcode's unrelated extraction churn.
- Commit messages are a single imperative title line.

CI (`.github/workflows/ci.yml`) is **manual for now** to save CI minutes (`gh workflow run CI --ref <branch>`).
Run it before a TestFlight upload. It checks:
1. **Generated client matches the committed spec.** Fails if you changed `OpenAPI/veckly-openapi.json`
   without regenerating.
2. **Committed spec vs production backend.** Informational only. A difference means a TestFlight build would
   talk to a backend with a different contract: deploy the backend and its migrations first.
3. **`VecklyTests`** on a macOS runner.

## Shipping to TestFlight

The app always talks to the production backend. Before uploading a build that depends on new backend
behaviour, make sure that backend code **and** its migrations are deployed (see Veckly-backend's README),
and that CI job 2 is green.
