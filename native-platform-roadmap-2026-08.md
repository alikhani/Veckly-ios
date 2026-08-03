# Plan: Native auth, Android och Apple Watch

**Skapad:** 2026-08-04  
**Status:** 🟡 Auth är nästa planerade produktslice; Android och Watch är sekvenserad backlog  
**Strategiskt beslut:** native först. Webben pausas som aktiv produkt­yta men behålls som referensimplementation.

## Mål

Göra Vecklys identitet enkel och trygg för vanliga hushåll på iOS, använda samma provider-neutrala identitet i en framtida Android-app och därefter bygga en fokuserad Apple Watch companion för kvällens middag och shopping.

## Nuläge

- Supabase Auth är kanonisk identitet och backend/RLS använder `auth.uid()`.
- iOS har fungerande Sign in with Apple.
- Access-/refresh-token sparas och sessioner kan förnyas.
- Email/password-anrop för sign-in och sign-up finns i `AuthSessionStore`, men konsument-UI saknas och debugbygget visar bara ett testkonto.
- Google-inloggning saknas.
- Kontoborttagning finns.

## Fas 1 — Email som komplett flöde

**Status:** 🔲 Ej påbörjad

- Lägg “Fortsätt med email” under Apple-knappen, visuellt sekundär.
- Separera registrering och inloggning utan att skapa en tung authportal.
- Stöd emailverifiering med tydligt “kontrollera inkorgen”-läge och återskick.
- Lägg glömt lösenord och reset via universal link/deep link tillbaka till appen.
- Mappa verkliga authfel till sv/en-copy: fel lösenord, redan registrerad email, svagt lösenord, utgången länk, rate limit och nätverksfel.
- Behåll session persistence, token refresh och kontoborttagning som gemensamma flöden oavsett provider.
- Testa cold launch med sparad session, utgången access token, giltig refresh token och återkallad session.

## Fas 2 — Google-inloggning

**Status:** 🔲 Ej påbörjad

- Aktivera Google-provider i Supabase och konfigurera iOS callback/deep-link-kontrakt.
- Välj Supabase-stödd native/OAuth-väg efter kontroll mot aktuella officiella SDK-dokument vid implementation.
- Skicka Google-sessionen till samma `AuthSessionStore`; bygg ingen separat backendidentitet.
- Hantera cancel, saknat nätverk, avvisad callback och providerfel utan att lämna appen i loadingläge.
- Behåll Sign in with Apple bredvid Google.

## Fas 3 — Kontolänkning och recovery

**Status:** 🔲 Ej påbörjad · blockerar bred authlansering

- Definiera och testa vad som händer när samma person använder Apple, Google och email med samma eller olika provider-email.
- Ingen runtime-länkning enbart på emailantagande. Använd verifierad provider-/Supabase-mekanism och kräv vid behov att användaren autentiserar båda sidor.
- Lägg en kontovy som visar aktiva inloggningsmetoder och möjliggör att lägga till en recovery-metod.
- Förhindra att sista fungerande inloggningsmetoden kopplas bort utan varning.
- Verifiera att hushåll, veckor, recept, feedback, entitlement och `appAccountToken` fortsätter peka på samma Supabase user-id.

## Fas 4 — Auth-releasegate

**Status:** 🔲 Ej påbörjad

- Två riktiga användare, två enheter och minst två providers.
- Ny installation, återinstallation, utloggning/inloggning och enhetsbyte.
- Offline launch med befintlig session och återanslutning.
- Avbruten Apple/Google-dialog och emailverifiering på annan enhet.
- Kontoborttagning och efterföljande nekad API-access.
- Privacy-/supportcopy och App Store metadata uppdaterad för providerlistan.

## Fas 5 — Native Android

**Status:** 🔲 Planerad efter auth-releasegaten

### Principer

- Kotlin + Jetpack Compose och modern coroutine-baserad concurrency.
- Samma Supabase-projekt, user-id, hushåll och RLS-regler som iOS.
- Generera eller bygg en tunn typad Kotlin-klient från samma committed OpenAPI-spec; ändra aldrig backendkontrakt separat för Android utan att iOS också verifieras.
- Första releasen täcker kärnloopen: auth, hushåll, vecka, planering/generering, receptval, shoppinglista, check-state och grundläggande receptvy.
- Google är primär bekväm provider på Android; email är gemensam recovery; befintliga Apple-konton måste kunna nå samma Veckly-identitet genom länkad metod.
- StoreKit-adaptern motsvaras senare av Google Play Billing, normaliserad till samma backend-entitlement.

### Startvillkor

- Auth- och kontolänkningskontraktet är verifierat på iOS.
- OpenAPI är stabil för kärnloopen.
- Nuvarande tvåpersonstest och first-five-review visar att produkten är värd att porta, inte fortfarande behöver grundläggande omtag.

## Fas 6 — Apple Watch companion

**Status:** 🔲 Planerad efter stabil iOS-kärna

### Watch v1

- Visa kvällens middag och enkel tids-/receptkontext.
- Visa aktuell veckas shoppinglista, grupperad kompakt.
- Bocka av/återställ shoppingvaror med samma idempotenta final-state-kontrakt som iPhone.
- Visa tydlig pending/offline-status; behåll tryck lokalt tills synk lyckas.
- Deep link/Handoff till rätt vy på iPhone för planering eller receptdetalj.

### Inte i Watch v1

- Ingen onboarding, hushållsadministration eller full veckogenerering.
- Ingen receptimport eller lång receptredigering.
- Ingen fristående betalning/paywall på klockan.
- Ingen egen parallell shoppingmodell.

### Tekniskt beslut före implementation

Utvärdera companion-sync via iPhone mot direkt backendaccess. Börja med minsta modell som ger pålitlig shopping i butik och undvik att kopiera auth-/refresh-tokenlogik till klockan om WatchConnectivity/Handoff räcker för v1.

## Sekvens

1. Fortsatt iOS-hushållstest.
2. Email auth.
3. Google auth.
4. Kontolänkning och auth-releasegate.
5. Native Android kärnloop.
6. Apple Watch companion.

Betalning kan fortsätta i sandbox parallellt, men aktiverade gates och nya plattformar får inte göra den fria kärnloopen mindre pålitlig.
