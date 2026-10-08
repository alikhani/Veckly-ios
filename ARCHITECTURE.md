# Veckly-ios architecture

SwiftUI + Swift Concurrency + Observation (`@Observable`), no third-party state management. Networking
is generated from the backend's OpenAPI spec (`scripts/generate-openapi-client.sh`).

## Layout

```
Veckly/
  VecklyApp, RootView, MainTabView, AppModel, AppRefreshCoordinator   app composition
  Features/<Feature>/   one folder per feature, flat inside (reference: Features/Week/)
  Core/Design/          shared UI building blocks (DismissibleErrorBanner, …)
  Generated/OpenAPI/    generated client — never edit by hand
  Generated/VecklyAPIClient.swift   hand-written adapter over the generated client (DTO → app model)
  *.swift               not-yet-migrated stores and views — still flat in Veckly/
VecklyTests/            unit tests (the commit gate)
VecklyUITests/          UI tests + screenshot scenarios (not a commit gate)
VecklyWidgets/          widget extension; shares WidgetSnapshot.swift by path, so do not move it
```

The Xcode project uses file-system-synchronized folders, so moving a file with `git mv` needs no
`project.pbxproj` change. New features go in `Features/<Feature>/`. Existing files move when you are
already doing real work in them.

## Layers

| Type | Owns | Must not |
|---|---|---|
| **View** (`*View`, `*Sheet`, `*Card`) | layout, pure UI state (`isExpanded`, confirmation dialogs) | call `apiClient`, call `handleUnauthorized`, coordinate several stores |
| **Section views** | render a part of a screen from **values and closures** | depend on `AppModel` or a screen model |
| **Screen model** (`WeekScreenModel`) | user intents, orchestration across stores, screen state (sheet, banners, undo) | depend on `AppModel` (takes concrete stores + closures; built by `static func live(_:)`) |
| **Store** (`WeekStore`, `ShoppingListStore`, …) | one domain's data: loading, caching, optimistic mutations, sync | know about other stores or views |
| **API adapter** (`VecklyAPIClient`) | calls the generated client, maps DTOs to app models and statuses to `APIError` | contain business rules |
| **Pure domain** (`WeekCalendar`, `WeekQualitySummary`, `IngredientScaler`, …) | deterministic logic | do I/O |

Each store declares the API slice it needs as a protocol (`WeekStoreAPIClient`, …).
`VecklyAPIClient` conforms, and tests pass a fake. Screen models are tested with real stores over
fake API clients (see `WeekScreenModelTests`).

`AppModel` is the composition root: it builds the stores and wires cross-store callbacks
(e.g. feedback → invalidate recommendations). Screens should receive what they need, not reach into
`AppModel` from deep views.

## Reference: the Week screen

```
MainTabView ──creates──▶ WeekScreenModel.live(appModel)
WeekTabView (renders)   ──intents──▶ WeekScreenModel ──▶ WeekStore / ShoppingListStore / PrepBatchStore …
   ├─ WeekHeroCards, WeekQualityCard, WeekDayList, WeekBanners, WeekToolbar   (values + closures)
   └─ WeekTabView+Sheets: one `sheet: WeekSheet?` enum routes every sheet
```

- Session resolution (household + userID, else `onUnauthorized`) happens once, in the model.
- After a week mutation, the model refreshes the shopping list. The view does not.
- All model state is `@MainActor`. Never write to `self` between two `async let` awaits.

## Checklist: new screen / feature

- [ ] Folder `Features/<Feature>/`; view + screen model if the screen coordinates more than one store
- [ ] Store mutations behind the store's API protocol; add the method to the protocol, not a direct `apiClient` call
- [ ] User-visible strings in `Localizable.xcstrings` (surgical edits only, validate with `json.load`); never translate user-owned content
- [ ] Unit tests for the model/store; screenshots of key states for layout changes (`VECKLY_UI_TEST_MODE=core-reader`)
- [ ] If the backend contract changed: regenerate the client and diff prod `/openapi.json` first (the simulator hits prod)

## Gates before commit

```
xcodebuild test -scheme Veckly -only-testing:VecklyTests -collect-test-diagnostics never
```
Don't run the full `VecklyUITests` as a gate. For visual changes, compare screenshots of the affected states.

## Known debt

- `WeekScreenModel` is split across `WeekScreenModel+*.swift`, so its dependencies and state setters
  are internal rather than `private` (Swift's `private` doesn't reach other files). Only the model's own
  extensions should write them.
- Week and Shopping (`Features/Shopping/`, `ShoppingScreenModel`) follow the target layout. The other
  features are still flat in `Veckly/` and reach `AppModel` through `@Environment`.
- `ShoppingListStore.swift` (~880 lines) also holds `ShoppingCategory`, `ShoppingListViewModelMapper`,
  `ShoppingListShareText` and `ShoppingListHandoffState`; split those out when next working there.
  `WeekStore.swift` (~1 340 lines) is the same kind of debt.
- The Shopping tab's seeded UI-test mode can't check or add items (the store has no sync context
  without a loaded summary), so those interactions are covered by `ShoppingScreenModelTests` only.
- `VecklyAPIClient.swift` is hand-written but lives in `Generated/`. Move it to `Core/` and split it per domain.
