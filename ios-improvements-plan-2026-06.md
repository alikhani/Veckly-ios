# iOS App Improvements — Implementation Plan (2026-06)

## Status: In progress

Recommended execution order, from highest daily-use value to lowest friction:

| Fas | Titel | Status |
|-----|-------|--------|
| 1 | Interaktiv shoppinglista | ✅ Klart (2026-06-11) |
| 2 | Ingredienser i receptvyn | ✅ Klart (2026-06-11) |
| 3 | Lås/lås upp dagar (koppla befintlig knapp) | ✅ Klart (2026-06-11) |
| 4 | Feedback på måltider (tumme upp/ner) | ✅ Klart (2026-06-11) |
| 5 | Hoppa över en dag | ✅ Klart (2026-06-11; stabilized 2026-06-16) |
| 6 | Household-vy stabilisering | ✅ Klart (2026-06-16) |
| 7 | Recept-vy stabilisering | ✅ Klart (2026-06-16) |

---

## Fas 1 — Interaktiv shoppinglista

**Status:** ✅ Klart (2026-06-11)

### Mål

Användaren ska kunna bocka av varor i appen medan de handlar. Bockar synkroniseras via
`PATCH /households/{householdId}/shopping-lists/{weekStartDate}/state` och persisteras
i backend. Alla hushållsmedlemmar ser samma bockat-status i realtid (eller vid nästa pull).

### Backend-kontrakt

- `GET /households/{id}/shopping-lists/{weekStartDate}/state`
  → `ShoppingListStateResponse { state: { checkedItems: [String] }, updatedAt: String? }`
- `PATCH /households/{id}/shopping-lists/{weekStartDate}/state`
  Body: `UpdateShoppingListStateRequest { expectedUpdatedAt: String?, state: { checkedItems: [String] } }`
  → `UpdateShoppingListStateResponse { ok: Bool, updatedAt: String? }`
  → `409 StaleShoppingListStateResponse { error: "STALE_SHOPPING_STATE", updatedAt: String? }`
- State-nycklarna är `itemKey` per `ShoppingListItem` (fältet finns redan i `VecklyAPITypes.swift`).

### Filer att röra

| Fil | Ändring |
|-----|---------|
| `VecklyAPIClient.swift` | Lägg till `func shoppingListState(...)` och `func updateShoppingListState(...)` |
| `ShoppingListStore.swift` | Lägg till `checkedItems: Set<String>`, `fetchState()`, `toggleItem(key:)` |
| `ShoppingListTabView.swift` | Rendera bockar interaktivt; ring `store.toggleItem(key:)` on tap |

### Detaljplan

**`VecklyAPIClient.swift`** — två nya metoder:
```swift
func shoppingListState(householdID: String, weekStartDate: String) async throws -> [String]
func updateShoppingListState(householdID: String, weekStartDate: String,
                             checkedItems: [String], expectedUpdatedAt: String?) async throws -> String?
```
Mappar de genererade `Operations.getShoppingListState` och `Operations.updateShoppingListState`.
Hanterar 409 (stale) genom att hämta om aktuell state och försöka igen (max 1 retry).

**`ShoppingListStore.swift`** — tillägg:
```swift
private(set) var checkedItems: Set<String> = []
private(set) var stateUpdatedAt: String?

func loadCurrentWeek(household: Household) async  // utöka med fetchState()
func toggleItem(key: String, householdID: String, weekStartDate: String) async
```
`toggleItem` optimistiskt togglar lokalt, sedan PATCH; vid fel återställ.

**`ShoppingListTabView.swift`** — bockar:
- Varje `ShoppingListItem`-rad: `Button` som togglar `store.toggleItem(key: item.itemKey, ...)`.
- Ikonval: `checkmark.circle.fill` (checked) / `circle` (unchecked).
- Checked items: `strikethrough` + `inkFaint`-färg.
- Sorteringsordning: unchecked first (sorteras om optimistiskt vid toggle).

### Testfall (UITest / unit)

- Tappa en vara → bockas av → persist PATCH kallas.
- Tappa igen → bockas av → persist PATCH kallas med tom array för den varan.
- 409-svar → retry med ny `expectedUpdatedAt` → lyckas.
- Offline-fel → optimistisk toggle återtas, errorToast visas.

---

## Fas 2 — Ingredienser i receptvyn

**Status:** ✅ Klart (2026-06-11)

### Mål

`RecipeDetailView` visar idag bara titel, beskrivning, portioner och taggar. Ska visa
ingredienslista och tillagningssteg — det är all data som krävs för att faktiskt laga rätten.
Data hämtas via `GET /households/{id}/recipes/{recipeId}` som returnerar fullständigt
`Recipe`-objekt med `ingredients: [RecipeIngredient]` och `steps: [RecipeStep]`.

### Backend-kontrakt

- `GET /households/{id}/recipes/{recipeId}`
  → `Recipe { id, title, description, servings, ingredients: [RecipeIngredient], steps: [RecipeStep], tags, prepTimeMinutes, cookTimeMinutes, ... }`
- `RecipeIngredient { item: String, amount: String?, unit: String?, category: String? }`
- `RecipeStep { instruction: String, durationMinutes: Int? }`
  (Se `Types.swift` rad ~3977–4070 för fullständiga fält.)

### Filer att röra

| Fil | Ändring |
|-----|---------|
| `VecklyAPIClient.swift` | Lägg till `func recipe(householdID: String, recipeID: String)` |
| `VecklyAPITypes.swift` | Lägg till `struct FullRecipe`, `RecipeIngredient`, `RecipeStep` |
| `RecipeDetailView.swift` | Ny `@State var fullRecipe: FullRecipe?`; hämta on appear; visa ingredienser + steg |

### Detaljplan

**`VecklyAPITypes.swift`** — nya typer:
```swift
struct RecipeIngredient: Decodable, Equatable {
    let item: String
    let amount: String?
    let unit: String?
    let category: String?
}
struct RecipeStep: Decodable, Equatable {
    let instruction: String
    let durationMinutes: Int?
}
struct FullRecipe: Decodable, Equatable, Identifiable {
    let id: String
    let title: String
    let description: String
    let servings: Int
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let tags: [String]
    let ingredients: [RecipeIngredient]
    let steps: [RecipeStep]
}
```

**`RecipeDetailView.swift`** — utökning:
- `RecipeDetailView` tar idag `WeekSummaryRecipe` som input. Lägg till:
  ```swift
  let householdID: String
  @State private var fullRecipe: FullRecipe?
  @State private var isLoading = false
  ```
- `.task { await loadFull() }` hämtar `GET /recipes/{id}`.
- Layout (ovanfrån):
  1. Titel + tidsinfo (befintlig)
  2. Beskrivning (befintlig)
  3. **Ingredienser** — rubrik "Ingredienser", lista `amount unit item` per rad, grupperade per `category` om satt
  4. **Tillagning** — rubrik "Gör så här", numrerade steg med `durationMinutes` om satt
  5. Taggar (befintlig, flytta ned)
- Under hämtning: behåll befintligt innehåll, visa skeleton/spinner bredvid ingredienssektionen.

**Prop-ändringar som propageras:**
- `WeekTabView` skickar `householdID: appModel.householdStore.activeHousehold?.id ?? ""` till `RecipeDetailView`.
- `todayPanel` likaså.

### Testfall

- `RecipeDetailView` med stubbed `FullRecipe` visar alla ingredienser.
- Tom ingredienslista: sektionen visas inte.
- Nätverksfel: befintlig data behålls, ingen kraschar.

---

## Fas 3 — Lås/lås upp dagar (koppla befintlig knapp)

**Status:** ✅ Klart (2026-06-11)

### Mål

Lock-knappen i `WeekDayRow` existerar sedan fas 1 i P1-arbetet (2026-06-10) men är lokal
state med ett `// TODO: wire to PATCH /api/weeks`-kommentar. Den ska nu skicka
`appendWeekPlanEvent` med `eventType: "meal_locked"` / `"meal_unlocked"` och reflektera
verkligt låst-state från backend vid laddning.

### Backend-kontrakt

- `POST /households/{id}/week-plan-events` body-variant för lock:
  ```json
  {
    "causedBy": "user",
    "eventType": "meal_locked",
    "day": "monday"
  }
  ```
  Och `"meal_unlocked"` för upplåsning.
- `GET /households/{id}/week-plans/{weekStartDate}/summary` returnerar `WeekPlanSummary`
  där varje `WeekPlanSummaryDay` har `isLocked: Bool`.
- iOS använder `day.isLocked` på view-modellen som sanningskälla. Separata klient-side
  set för locked state ska inte introduceras igen.

### Filer att röra

| Fil | Ändring |
|-----|---------|
| `VecklyAPIClient.swift` | `func appendWeekPlanEvent(householdID:weekStartDate:event:)` |
| `WeekStore.swift` | `lockedDays` härleds från `dayRows`; `toggleLock` uppdaterar raden optimistiskt |
| `WeekTabView.swift` | Läser `day.isLocked`; anropar store-metod |

### Detaljplan

**`VecklyAPIClient.swift`** — ny metod:
```swift
func appendWeekPlanEvent(
    householdID: String,
    weekStartDate: String,
    eventType: String,   // "meal_locked" | "meal_unlocked" | "day_skipped" | ...
    day: String          // "monday" | "tuesday" | ...
) async throws
```
Mappar `Operations.appendWeekPlanEvent` med rätt `causedBy: "user"`.

**`WeekStore.swift`** — tillägg:
```swift
var lockedDays: Set<Weekday> { Set(dayRows.filter(\.isLocked).map(\.weekday)) }

func toggleLock(day: WeekDayRowViewModel, household: Household) async
```
`toggleLock` skickar rätt event beroende på aktuell state, optimistisk uppdatering lokalt.
`lockedDays` härleds från `dayRows`, som populeras från `WeekPlanSummaryDay.isLocked`.

**`WeekTabView.swift`** — uppdatering:
- Ta bort `@State private var lockedDayIds: Set<String>`.
- `isLocked` läses från `day.isLocked`.
- `onToggleLock` anropar `Task { await appModel.weekStore.toggleLock(day: day, household: household) }`.

### Testfall

- Lock: optimistisk toggle → API-anrop → state kvarstår.
- Unlock: ditto.
- Fel: toggle återtas.
- State korrekt vid app-start (laddat från backend).

---

## Fas 4 — Feedback på måltider (tumme upp/ner)

**Status:** ✅ Klart (2026-06-11)

### Mål

En familj ska kunna säga "vi gillande det här" eller "inte igen" direkt i appen.
Feedback lagras via `PUT /households/{householdId}/meal-feedback` och påverkar nästa veckas förslag på webben.
Feedbackknapparna visas i expanderat kortläge (under receptbeskrivning).

### Backend-kontrakt

- `GET /households/{householdId}/meal-feedback`
  → `ListMealFeedbackResponse { feedback: { [mealId]: { vote, signal? } }, items: [...] }`
- `PUT /households/{householdId}/meal-feedback`
  Body: `UpsertMealFeedback { mealId, feedback: { vote: "up"|"down", signal? } | null }`
  → `{ ok: true }`
- Feedback är user-owned men household-scoped via RLS (`householdId + userId + mealId`).

### Filer att röra

| Fil | Ändring |
|-----|---------|
| `VecklyAPIClient.swift` | `func submitMealFeedback(householdID:mealID:vote:)` |
| `WeekStore.swift` | `feedback: [String: MealVote]`; ladda befintlig feedback; `submitFeedback(...)` |
| `WeekTabView.swift` | Tumme-knappar i `expandedBody`; markera befintlig röst om satt |

### Detaljplan

**`VecklyAPITypes.swift`** — ny typ:
```swift
enum MealVote: String, Codable { case up, down }
```

**`WeekStore.swift`** — tillägg:
```swift
private(set) var mealFeedback: [String: MealVote] = []  // keyed by mealId

func submitFeedback(mealID: String, vote: MealVote, household: Household) async
```

**`WeekTabView.swift` / `WeekDayRow`** — i `expandedBody`:
```swift
HStack(spacing: 16) {
    FeedbackButton(vote: .up,   isSelected: store.mealFeedback[recipe.id] == .up,   action: { ... })
    FeedbackButton(vote: .down, isSelected: store.mealFeedback[recipe.id] == .down, action: { ... })
}
```
`FeedbackButton`: `hand.thumbsup.fill` / `hand.thumbsdown.fill` SF Symbols. Markerat = hearthOrange.

Befintlig röst laddas via separat `GET /households/{householdId}/meal-feedback`.

### Testfall

- Tumme upp → `mealFeedback[id] == .up`, API-anrop skickas.
- Rösta igen → sama röst: inget nytt anrop (debounce / idempotent).
- Rösta motsa → rösten ändras.
- Befintlig röst visas korrekt vid laddning.

---

## Fas 5 — Hoppa över en dag

**Status:** ✅ Klart (2026-06-11)

### Mål

Lägga till "Hoppa över" i expanderat kortläge. Hoppad dag visas som tom/grå med möjlighet
att ångra. Använder `appendWeekPlanEvent` med `eventType: "day_skipped"` /
`"day_unskipped"` (båda finns i det genererade schema, se `Types.swift` rad ~1431).

### Backend-kontrakt

Samma `appendWeekPlanEvent` som fas 3. Event-struktur:
```json
{
  "causedBy": "user",
  "eventType": "day_skipped",
  "day": "tuesday"
}
```
Hämtad state: `WeekPlanSummaryDay.state == "skipped"` per dag. iOS ska läsa
`day.isSkipped` från mapperns output och inte hålla en separat sanningskälla i vyn.

### Filer att röra

| Fil | Ändring |
|-----|---------|
| `WeekStore.swift` | `skippedDays` härleds från `dayRows`; `toggleSkip(day:household:)` uppdaterar raden optimistiskt |
| `WeekTabView.swift` | "Hoppa över"-knapp i `expandedBody`; hoppad dag = grå card + "Hoppade över" |

### Detaljplan

**`WeekStore.swift`** — tillägg parallellt med fas 3:
```swift
var skippedDays: Set<Weekday> { Set(dayRows.filter(\.isSkipped).map(\.weekday)) }

func toggleSkip(day: WeekDayRowViewModel, household: Household) async
```

**`WeekTabView.swift` / `WeekDayRow`** — i `expandedBody`:
- Knapp: `"Hoppa över" / "Ångra"`, plain style med `inkMid`-färg.
- Hoppade kort: `cardTitleCollapsed` visar "Hoppar över" istället för måltiteln.
  Kortet grå-tonas via opacity eller `canvas`-bakgrund.
- Hoppad dag kollapsar automatiskt efter bekräftelse.

**Visuell status i header:**
- Om `store.skippedDays.contains(day.id)`: visa "Hoppar" badge bredvid dagsetiketten,
  lika stil som "Today"-badgen men grå. Lås-knappen döljs (hoppad dag kan inte låsas).

### Testfall

- Hoppa → optimistisk update → API-anrop → kort grå-tonas.
- Ångra → återgår till normal.
- State korrekt vid app-start.
- Hoppad dag: lås-knapp inte synlig.

---

## Fas 6 — Household-vy stabilisering

**Status:** ✅ Klart (2026-06-16)

### Utfört

- `HouseholdStore` har household-scopad cache för members, profile och invites.
- Byte av active household rensar household-scopad state så föregående hushåll inte läcker i vyn.
- Invite-accept returnerar joined household id och väljer rätt hushåll direkt.
- Household members/profile-vyer laddar med `.task(id: household.id)` och visar loading/error/empty-state.
- Invite-token kan kopieras från sheeten och landing-token state nollas när input ändras.
- Tester täcker per-household cache, invite accept och active-household byte.

---

## Fas 7 — Recept-vy stabilisering

**Status:** ✅ Klart (2026-06-16)

### Utfört

- `RecipeStore` har household-scopad cache och exponerar load-fel istället för att tyst cacha tom lista.
- Create/update håller full-recipe-cachen uppdaterad.
- Arkivering använder optimistisk remove med rollback vid API-fel.
- Receptlistan laddar via `.task(id: activeHousehold.id)`, har retry/empty-state och länkar rader till `RecipeDetailView`.
- Sök matchar titel, beskrivning och tags.
- Receptformuläret trimmar input, blockerar dubbeloperationer under save/import/fill, använder `RecipeStore` för import/AI-fill och varnar vid osparade ändringar.
- Tester täcker household-cache, load-fel, full-recipe-cache och arkiv-rollback.

---

## Övergripande arkitekturmönster

Alla faser följer samma mönster för att hålla koden konsekvent:

```
WeekTabView / ShoppingListTabView
  ↓ actions
AppModel.weekStore / shoppingListStore
  ↓ API calls
VecklyAPIClient (generated transport)
  ↓ HTTP
Veckly-backend (Vercel)
```

- **Optimistiska uppdateringar**: lokalt state ändras omedelbart; API-fel återtar.
- **Ingen polling**: data hämtas vid `onAppear` + manuell pull-to-refresh (toolbar-knapp finns).
- **Ingen tredjepartsdependency**: SwiftUI `.popover`, `.sheet`, native list — inga nya paket.
- Alla nya fält i `WeekDayRowViewModel` läggs till som optionals för att inte bryta
  `WeekViewModelMapper`-testerna (`WeekViewModelMapperTests.swift`).

---

## Fas 8 — Veckovy UX-polish

**Status:** ✅ Klart (2026-06-17)

### Utfört

**Datumgräns vid midnatt (timezone-fix)**
`WeekCalendar.swift` och `WeekStore.swift` använde UTC-kalender för dagjämförelser. I Stockholm (UTC+2) innebär det att kl 00:55 onsdag fortfarande räknas som tisdag. Bytt till `Calendar.current` (enhetens lokaltid) genomgående i `isToday` och `isPast`.

**Passerade dagar tonas ner**
`WeekDayRowViewModel` har ett nytt fält `isPast: Bool`. `CompactDayRow` applicerar `opacity(0.45)` på hela raden när `isPast` är sant. Det orangea "Plan"-alternativet döljs för passerade dagar. Swipe-action är borttagen för passerade dagar via `SwipeSkipModifier` (ViewModifier som branchar på modifier-nivå snarare än inuti `swipeActions { }` — undviker ghost-hitregioner i UIKit).

**"Skip this day" tillgänglig utan scroll**
`RecipeDetailView` renderar nu ett skip/plan-alternativ allra överst i sheeten, ovanför receptets titel och innehåll. Tidigare krävdes scroll hela vägen ned. Parametrarna `isSkipped: Bool?` och `onSkip: (() -> Void)?` är optional med nil-default, så call sites som inte skickar in dag-kontext (t.ex. receptfliken) påverkas inte.

**Swipe-guard via ViewModifier**
Villkoret `if !day.isPast` inuti en `swipeActions { }` builder lämnar en osynlig hit-testregion på cellen i UIKit. Ersatt med `SwipeSkipModifier: ViewModifier` som inte dekorerar cellen alls när `isPast` är sant.

### Filer som ändrades

| Fil | Vad |
|-----|-----|
| `WeekCalendar.swift` | `isToday` och `isPast` använder `Calendar.current` |
| `WeekStore.swift` | `isPast` i `WeekDayRowViewModel`; `WeekViewModelMapper` beräknar det från lokal kalender |
| `WeekTabView.swift` | `SelectedDayRecipe` struct för dag+recept-kontext; `SwipeSkipModifier`; opacity/Plan-dölj för past rows |
| `RecipeDetailView.swift` | `skipDayRow` längst upp i scroll-innehållet; optional `isSkipped`/`onSkip` parametrar |

---

## Nästa steg efter fas 5

När appen är write-capable i planeringssidan är dessa naturliga nästa steg:

- **Bjud in partner** — `POST /households/{id}/invites` är implementerat i backend; UI saknas.
- **Onboarding** — ny användare utan veckoplan möts av tomt state; 3-stegs
  preferensflöde kan mappa mot `appendWeekPlanEvent` med `planning_request_updated`.
- **Notiser** — "Veckans plan är klar" push-notis när ny vecka genereras.
