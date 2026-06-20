# Hushållsflik och språkval — implementationsplan (2026-06)

## Status: Implementerad (2026-06-19)

## Beslut

- Fliken `Inställningar` ersätts av `Hushåll`.
- Hushållsvyn ska vara ett nav för hushållets identitet, medlemmar och planeringspreferenser — inte en generell samlingsplats för all sekundär navigation.
- Personprofiler för exempelvis barn och deras individuella smakpreferenser ingår inte i denna version.
- Appspråk ska kunna väljas som `System`, `Svenska` eller `English`.
- Språkvalet är lokalt för användaren/enheten och påverkar inte övriga hushållsmedlemmar.
- Befintliga backend-kontrakt för hushåll, medlemmar, inbjudningar och hushållsprofil återanvänds. Ingen backendändring krävs i denna leverans.

## Mål

1. Ge den fjärde huvudfliken ett innehåll som motsvarar Vecklys hushållscentrerade produktmodell.
2. Göra hushållets namn, sammansättning och viktigaste åtgärder begripliga utan att användaren först behöver tolka en inställningslista.
3. Behålla alla befintliga funktioner: byt namn, medlemmar/inbjudningar, planeringspreferenser, logga ut och radera konto.
4. Låta användaren byta UI- och API-språk mellan systemval, svenska och engelska utan att starta om appen.
5. Behålla ägar- och medlemsbehörigheter oförändrade.

## Utanför scope

- Personprofiler eller smakprofiler per hushållsperson.
- Individuell måltidsfeedback per person.
- Profilbilder eller uppladdade hushållsbilder.
- Ändringar av rekommendationsmotorn.
- Prenumerations-, provperiods- eller betalningshantering.
- Nya hjälp-, integritets- eller feedbackflöden som saknar befintlig destination.
- Hantering av flera aktiva hushåll eller en ny hushållsväljare.
- Ändringar i backend eller OpenAPI-specifikationen.

## Informationsarkitektur

### Flik

- Tabbetikett: `Hushåll` / `Household`.
- SF Symbol: `person.2` eller `house`; välj `person.2` i första implementationen eftersom innehållet gäller människorna och deras gemensamma planering, inte bostaden.
- Navigationstitel: `Hushåll` / `Household`.

### Hushållsvyn, uppifrån och ned

#### 1. Hushållskort

Visar:

- Hushållets namn.
- Sammanfattning från den cachelagrade hushållsprofilen, exempelvis `2 vuxna · 1 barn`.
- Rollen `Ägare` / `Medlem` som sekundär information där den behövs för att förklara behörighet.
- Neutral hushållsikon med SF Symbol; ingen avatarfunktion introduceras.

Tillstånd:

- Om profilen laddas: visa hushållsnamnet direkt och en diskret placeholder för sammanfattningen.
- Om profil saknas: visa endast hushållsnamn och roll; skicka användaren till planeringspreferenser för att komplettera.
- Om hushåll saknas under bootstrap: visa ett laddningstillstånd, inte tomma eller destruktiva kontroller.

#### 2. Hushållet

Navigationsrader:

- `Medlemmar och inbjudningar` → befintlig `HouseholdMembersView`.
  - Visa medlemsantal som trailing-värde när detaljerna är laddade.
  - Ägarens befintliga möjlighet att skapa och återkalla inbjudningar behålls.
- `Planering och mat` → befintlig `HouseholdProfileView`.
  - Samlar hushållsstorlek, matlagningsdagar, prioriteringar och ingredienser att undvika.
- `Byt namn på hushållet` → befintlig `RenameHouseholdView`.
  - Visas endast för ägare.
  - Medlemmar ser hushållsnamnet men ingen redigeringskontroll.

`HouseholdMembersView`, `HouseholdProfileView` och `RenameHouseholdView` fortsätter vara separata destinationsvyer. Huvudvyn ska inte absorbera deras formulär eller nätverkslogik.

#### 3. App

- Rad `Språk` visar aktuellt val som trailing-värde.
- Raden öppnar `LanguageSelectionView`.
- Alternativ:
  - `System` / `System`
  - `Svenska` (språkets eget namn i båda UI-språken)
  - `English` (språkets eget namn i båda UI-språken)
- Det valda alternativet markeras med checkmark.
- Byte ska slå igenom omedelbart när användaren går tillbaka till Hushållsvyn.

#### 4. Konto

- `Logga ut` är en vanlig kontorad, inte en primär knapp.
- `Radera konto` ligger sist i en separat destruktiv sektion med befintlig bekräftelsedialog och felhantering.
- Befintlig raderingscopy och footer behålls om inget copyproblem upptäcks under implementationen.

## Visuell riktning

- Använd en `ScrollView` för navvyn och `VecklyCard` för hushållskortet och grupperna. Undvik att låta hela startsidan se ut som ett systemformulär.
- Behåll `Form` i redigeringsvyerna `HouseholdProfileView`, `RenameHouseholdView`, `HouseholdMembersView` och `LanguageSelectionView`; de är uppgiftsorienterade formulär/listor.
- Hushållets namn använder Georgia-displaystilen via `VecklyDesign.Typography.displayHeading`.
- Hearth Orange används för aktivt val och mindre accenter, inte som bakgrund för varje rad.
- Stöd Dynamic Type och låt sammanfattningen radbrytas hellre än att trunkeras.
- Alla navigationsrader ska ha minst 44 pt träffyta och tydlig VoiceOver-etikett.

## Teknisk design

### 1. Ny språkmodell

Skapa `AppLanguage.swift` med:

```swift
enum AppLanguage: String, CaseIterable, Codable {
    case system
    case swedish
    case english
}

@MainActor
@Observable
final class AppLanguageStore {
    private(set) var selection: AppLanguage
    func select(_ language: AppLanguage)
}
```

Ansvar:

- Läs och skriv `UserDefaults`-nyckeln `veckly.app-language`.
- Fallbacka till `.system` om värdet saknas eller är okänt.
- Exponera effektiv `Locale`:
  - system → systemets aktuella/autouppdaterande locale
  - swedish → `Locale(identifier: "sv")`
  - english → `Locale(identifier: "en")`
- Exponera API-språksignal från samma källa, så UI och backend aldrig får separata språkval.

`AppLanguageStore` ägs av `AppModel`, på samma nivå som övriga appgemensamma stores. Språk är appkonfiguration, inte hushållsdata, och ska därför inte återställas vid utloggning eller byte av hushåll.

### 2. Koppla språk till SwiftUI

I appens rot:

- Injicera `AppLanguageStore` i environment.
- Sätt `.environment(\.locale, appModel.languageStore.effectiveLocale)` på rotinnehållet.
- Säkerställ att en ändring av `selection` invalidierar rotvyn så att `Text` med lokaliseringsnycklar renderas om direkt.

SwiftUI använder locale-värdet i environment för lokaliserade `Text`-värden. För strängar som skapas genom `L10n.string` och `L10n.format` ska den explicita effektiva localen skickas till Foundations lokaliserings-API, annars kan dessa texter fortsätta följa systemspråket trots användarens val.

Refaktorera `L10n` så att:

- `string` slår upp nyckeln med vald locale.
- `format` använder samma locale för både stränguppslag och formatering.
- systemläget bevarar nuvarande beteende.
- fallback för saknad svensk sträng förblir engelska genom katalogens development region.

Undvik att skriva till Apples globala `AppleLanguages`-default eller kräva omstart; språkvalet ska ägas av appen.

### 3. Koppla språk till API-anrop

Refaktorera `AppLocalePreference.acceptLanguageHeader` till att använda det sparade appvalet:

- system → nuvarande header byggd från `Locale.preferredLanguages`, inklusive engelsk fallback.
- svenska → `sv, en;q=0.8`.
- engelska → `en`.

Alla anropsvägar måste fortsätta använda samma resolver:

- den handskrivna API-wrappen,
- den OpenAPI-baserade klienttransporten,
- manuella `URLSession`-anrop.

Verifiera med `rg "Accept-Language|acceptLanguageHeader"` att ingen anropsväg fortfarande läser systemspråket direkt. Språkbytet behöver inte återskapa klienten om headern beräknas vid varje request.

### 4. Hushållsvyn

Ersätt `SettingsTabView` med `HouseholdTabView`.

Ansvar:

- Läsa aktivt hushåll och cachelagrad hushållsprofil från `HouseholdStore`.
- Presentera hushållskort och navigationssektioner.
- Behålla endast lokal UI-state för dialogerna `showDeleteConfirmation`, `isDeletingAccount` och `deleteErrorMessage`.
- Anropa befintliga `AppModel.signOut()` och `AppModel.deleteAccount()`.
- Inte göra egna API-anrop; data laddas redan i `AppModel.loadCoreReader()` och destinationsvyerna ansvarar för sina uppdateringar.

Extrahera små privata komponenter när huvudvyn annars blir svårläst:

- `HouseholdSummaryCard`
- `HouseholdNavigationRow`
- eventuellt en generell sektionscontainer om minst två sektioner får identisk markup

Skapa inte en generell komponent innan två verkliga användningar finns.

### 5. Navigation och filnamn

- `MainTabView` ska skapa `HouseholdTabView()` i den befintliga separata `NavigationStack` som ägs av fliken.
- Byt tabnyckel från `tabs.settings` till `tabs.household`.
- Behåll gamla settings-nycklar som fortfarande används för konto- och preferenscopy; radera bara verifierat oanvända nycklar.
- Ta bort `SettingsTabView.swift` när alla callsites och tester pekar på den nya vyn.

## Lokaliseringscopy

Lägg minst till följande semantiska nycklar i `Localizable.xcstrings` med engelska och svenska värden:

| Nyckel | Svenska | Engelska |
|---|---|---|
| `tabs.household` | Hushåll | Household |
| `household.summary.adultsChildren` | lokaliserat pluralformat | localized plural format |
| `household.role.owner` | Ägare | Owner |
| `household.role.member` | Medlem | Member |
| `household.planningFood` | Planering och mat | Planning and food |
| `household.rename` | Byt namn på hushållet | Rename household |
| `app.section` | App | App |
| `app.language` | Språk | Language |
| `language.system` | System | System |
| `language.swedish` | Svenska | Svenska |
| `language.english` | English | English |

Använd String Catalogs pluralvariationer för `vuxen/vuxna` och `barn/children`; bygg inte pluraler genom strängkonkatenering i vyn.

## Behörighetsmatris

| Funktion | Ägare | Medlem |
|---|---:|---:|
| Se hushållsnamn och sammanfattning | Ja | Ja |
| Se medlemmar | Ja | Ja |
| Skapa/återkalla inbjudan | Ja | Nej, enligt befintlig iOS-behörighet |
| Ändra planeringspreferenser | Behåll nuvarande beteende | Behåll nuvarande beteende |
| Byta hushållsnamn | Ja | Nej |
| Byta appspråk | Ja | Ja |
| Logga ut/radera eget konto | Ja | Ja |

Implementation ska inte enbart gömma ägarkontroller visuellt; befintliga backendkontroller fortsätter vara säkerhetsgränsen.

## Filplan

| Fil | Planerad ändring |
|---|---|
| `Veckly/MainTabView.swift` | Byt flik från Settings till Household, ny label och symbol. |
| `Veckly/HouseholdTabView.swift` | Ny navvy med sammanfattning, hushåll, app och konto. |
| `Veckly/SettingsTabView.swift` | Tas bort efter migration. |
| `Veckly/LanguageSelectionView.swift` | Ny checkmark-lista för System/Svenska/English. |
| `Veckly/AppLanguage.swift` | Språkmodell, persistence, effektiv locale och headerregler. |
| `Veckly/AppModel.swift` | Äg och exponera `AppLanguageStore`; rensa den inte vid logout. |
| `Veckly/VecklyApp.swift` eller `Veckly/RootView.swift` | Injicera vald locale och språkstore i vyns environment. |
| `Veckly/L10n.swift` | Gör explicit språkval gemensamt för UI-formatering och `Accept-Language`. |
| `Veckly/Generated/VecklyAPIClient.swift` | Säkerställ att request-headern hämtas dynamiskt från språkresolvern. |
| `Veckly/Localizable.xcstrings` | Lägg till tab-, hushålls-, språk- och pluralnycklar. |
| `VecklyTests/AppLanguageTests.swift` | Unit tests för persistence, locale och headers. |
| `VecklyUITests/VecklyUITests.swift` | UI-flöden för Hushållsfliken och runtime-språkbyte. |

Om Xcode-projektet inte använder filsystems-synkroniserade grupper måste de nya Swift-filerna även läggas till i app-targeten i `project.pbxproj`.

## Implementationsordning

### Fas 1 — Språkets grundmodell

1. Introducera `AppLanguage`, `AppLanguageStore` och `UserDefaults`-persistence.
2. Lägg unit tests för default, explicit val, okänt sparat värde och headers.
3. Koppla vald locale till SwiftUI-roten.
4. Refaktorera `L10n` och `AppLocalePreference` till samma språkresolving.
5. Verifiera att befintligt systemläge fortfarande klarar svenska och engelska UI-testet.

Leveranskriterium: språkmodell och befintlig UI beter sig korrekt utan att Hushållsvyn ännu är ändrad.

### Fas 2 — Hushållsnav

1. Skapa `HouseholdTabView` med hushållskort och befintliga destinationer.
2. Flytta kontoåtgärderna och deras dialog-/felstate från `SettingsTabView`.
3. Koppla `MainTabView` till den nya vyn och byt tabcopy/symbol.
4. Kontrollera ägar- och medlemsläge separat.
5. Ta bort `SettingsTabView` när inga referenser återstår.

Leveranskriterium: ingen befintlig inställningsfunktion har försvunnit och fliken upplevs som hushållsorienterad.

### Fas 3 — Språkväljare

1. Skapa `LanguageSelectionView` och länka från sektionen App.
2. Lägg lokaliseringsnycklar och pluralvarianter.
3. Verifiera direkt byte svenska ↔ engelska ↔ system utan omstart.
4. Verifiera att nästa API-request använder rätt `Accept-Language`.

Leveranskriterium: både statisk SwiftUI-copy, dynamisk `L10n`-copy och API-header följer samma val.

### Fas 4 — Tillgänglighet och regression

1. Lägg VoiceOver-labels och stabila accessibility identifiers för flik, språkval och kontoåtgärder.
2. Testa Dynamic Type, mörkt läge och långa engelska/svenska strängar.
3. Kör unit tests, UI tests och slutlig simulatorbuild.
4. Sök efter kvarvarande `tabs.settings`, `SettingsTabView`, hårdkodade språklabels och direkta `Locale.preferredLanguages` utanför resolvern.

## Testplan

### Unit tests — `AppLanguageTests`

- Första start utan sparat värde ger `.system`.
- Sparat `.swedish` och `.english` återställs i en ny store-instans.
- Okänt/korrupt värde fallbackar till `.system`.
- Systemläge bygger header från testbar preferred-language-input.
- Svenskt val ger `sv, en;q=0.8`.
- Engelskt val ger `en`.
- Effektiv locale har rätt primärt språk för alla tre val.
- Språkval överlever logout eftersom språkstore inte nollställs.

Injicera en separat `UserDefaults` suite och en preferred-languages-provider i testerna; unit tests ska inte ändra utvecklingsmaskinens globala defaults.

### UI tests

- Core-reader startar med fliken `Household`; hushållsnamnet syns.
- Svenskt systemläge visar `Hushåll` och svenska sektionsnamn.
- Engelskt systemläge visar `Household`.
- Välj `Svenska` från engelskt systemläge → tabbar och Hushållsvy byter språk direkt.
- Välj `English` från svenskt systemläge → UI byter direkt.
- Välj `System` → UI återgår till launchmiljöns språk.
- Ägare ser `Byt namn på hushållet`; medlem gör det inte.
- `Logga ut` fungerar från den nya vyn.
- `Radera konto` visar bekräftelse och kan avbrytas utan API-anrop.

För runtime-språktester ska UI-testläget kunna startas med ett isolerat sparat språkval eller rensa test-suiten vid launch, så tester inte påverkar varandra.

### Manuell verifiering

- Hushållskort med 1 vuxen/0 barn, flera vuxna/1 barn och flera barn använder korrekt plural.
- Laddning och saknad hushållsprofil ger begripliga tillstånd.
- Medlemsantal uppdateras efter accepterad inbjudan.
- Tillbakagång från redigerad hushållsprofil uppdaterar sammanfattningskortet.
- Språkbyte påverkar datum, veckodagar och format enligt vald locale.
- En API-request efter varje språkval har förväntad `Accept-Language`.
- Mörkt läge, största Dynamic Type och VoiceOver fungerar utan klippning eller otydliga destruktiva kontroller.

## Definition of done

- Fjärde fliken heter `Hushåll`/`Household` och använder den nya navvyn.
- Samtliga funktioner från `SettingsTabView` är nåbara med samma behörigheter.
- Hushållskortet visar aktivt hushåll och korrekt pluraliserad sammansättning när profil finns.
- Språkvalet System/Svenska/English persisterar lokalt och slår igenom utan omstart.
- SwiftUI-copy, `L10n`-strängar, datumformat och `Accept-Language` följer samma effektiva språk.
- Personprofiler har inte introducerats i schema, API eller UI.
- Nya unit tests och UI tests är gröna.
- Simulatorbuild är grön utan nya warnings.
- Svensk och engelsk copy är komplett i String Catalog.

## Risker och motåtgärder

### Blandat språk efter runtime-byte

Risk: `Text` följer environment-locale medan `L10n.string` fortsätter använda systemets locale.

Motåtgärd: en gemensam språkresolver och UI-test som byter språk medan appen kör.

### API och UI använder olika språk

Risk: request-headern fortsätter läsa `Locale.preferredLanguages` vid explicit appval.

Motåtgärd: härled både locale och header från samma `AppLanguage` och testa headers separat.

### Hushållsvyn blir en ny inställningslista

Risk: en ren `Form`-migration ändrar bara rubriken men inte upplevelsen.

Motåtgärd: separat sammanfattningskort och tydliga grupper; formulär används först efter navigation till en redigeringsuppgift.

### Scope växer mot personprofiler

Risk: nya rader eller datatyper börjar antyda individsmak utan stöd i backend.

Motåtgärd: håll denna leverans till hushållsaggregatet och dokumentera personprofiler som ett separat framtida initiativ.

## Senare initiativ: personprofiler

Följande sparas för en egen produkt- och backendplan:

- Hushållspersoner som är separata från autentiserade kontomedlemmar.
- Namn, vuxen/barn, åldersgrupp och hårda kostkrav.
- Mjuka ogillanden och favorit/ratade rätter per person.
- Individuell måltidsfeedback och regler för målkonflikter inom hushållet.
- Migrering från dagens aggregerade `adults`, `children` och `avoidIngredients`.

Det initiativet ska inte påbörjas genom att utöka den här Hushållsvyn innan domänmodell och rekommendationslogik är beslutade.
