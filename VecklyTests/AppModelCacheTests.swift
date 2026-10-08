import Foundation
import Testing
@testable import Veckly

@MainActor
struct AppModelCacheTests {
    static let unreachable = AppEnvironment(
        apiBaseURL: URL(string: "http://127.0.0.1:1")!,
        supabaseURL: URL(string: "http://127.0.0.1:1")!,
        supabaseAnonKey: "test"
    )
    static let userID = "33333333-3333-3333-3333-333333333333"
    static let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Familjen", role: .owner)

    static func scope(language: String = "sv") -> CacheScope {
        CacheScope(userID: userID, householdID: household.id, language: language)
    }

    static func weekSummary() -> WeekSummary {
        let week = WeekCalendar.currentWeekStartDate()
        return WeekSummary(
            household: SummaryHousehold(id: household.id, name: household.name),
            weekStartDate: week,
            updatedAt: "v1",
            days: Weekday.allCases.enumerated().map { index, weekday in
                WeekSummaryDay(
                    dayOfWeek: weekday,
                    date: WeekCalendar.addDays(to: week, offset: index),
                    state: .planned,
                    recipe: WeekSummaryRecipe(id: "r\(index)", title: "Cachad rätt \(index)", description: "", servings: 4, prepTimeMinutes: 10, cookTimeMinutes: 10, tags: [])
                )
            }
        )
    }

    static func shoppingSnapshot() -> ShoppingListSnapshot {
        ShoppingListSnapshot(
            summary: ShoppingListSummary(
                household: SummaryHousehold(id: household.id, name: household.name),
                weekStartDate: WeekCalendar.currentWeekStartDate(),
                updatedAt: "s1",
                groups: [ShoppingListGroup(category: "Dairy", items: [
                    ShoppingListItem(itemKey: "dairy:mjölk:", label: "Mjölk", amount: nil, unit: nil, checked: false),
                ])]
            ),
            state: ShoppingListSharedState(checkedItems: [], pantryStock: [:], customItems: []),
            stateUpdatedAt: "t1",
            categoryOrder: nil
        )
    }

    @Test func signingOutDeletesTheDiskCaches() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AppModelCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let weekCache = WeekStoreDiskCache(baseDirectory: directory)
        let shoppingCache = ShoppingListStoreDiskCache(baseDirectory: directory)
        weekCache.saveWeek(Self.weekSummary(), scope: Self.scope())
        shoppingCache.saveList(Self.shoppingSnapshot(), scope: Self.scope())
        let model = AppModel(
            environment: Self.unreachable,
            authSessionStore: AuthSessionStore(authClient: StubAuthService(), sessionStorage: InMemoryAuthSessionStorage()),
            weekCache: weekCache,
            shoppingCache: shoppingCache,
            householdSnapshotStore: HouseholdSnapshotDiskStore(baseDirectory: directory)
        )
        let week = WeekCalendar.currentWeekStartDate()
        #expect(weekCache.loadWeek(scope: Self.scope(), weekStartDate: week) != nil)

        model.signOut()

        #expect(weekCache.loadWeek(scope: Self.scope(), weekStartDate: week) == nil)
        #expect(shoppingCache.loadList(scope: Self.scope(), weekStartDate: week) == nil)
    }

    // MARK: Cold start from disk

    private struct ColdStart {
        let model: AppModel
        let storage: InMemoryAuthSessionStorage
        let auth: StubAuthService
        let weekCache: WeekStoreDiskCache
        let shoppingCache: ShoppingListStoreDiskCache
        let snapshots: HouseholdSnapshotDiskStore
        let directory: URL
    }

    private func makeColdStart(
        session: AuthSession?,
        seedCaches: Bool = true,
        seedSnapshot: Bool = true
    ) -> ColdStart {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AppModelColdStart-\(UUID().uuidString)", isDirectory: true)
        let weekCache = WeekStoreDiskCache(baseDirectory: directory)
        let shoppingCache = ShoppingListStoreDiskCache(baseDirectory: directory)
        let snapshots = HouseholdSnapshotDiskStore(baseDirectory: directory)
        if seedCaches {
            weekCache.saveWeek(Self.weekSummary(), scope: Self.scope(language: CacheScope.currentLanguage))
            shoppingCache.saveList(Self.shoppingSnapshot(), scope: Self.scope(language: CacheScope.currentLanguage))
        }
        if seedSnapshot { snapshots.save(Self.household, userID: Self.userID) }
        let storage = InMemoryAuthSessionStorage(session: session)
        let auth = StubAuthService()
        let model = AppModel(
            environment: Self.unreachable,
            authSessionStore: AuthSessionStore(authClient: auth, sessionStorage: storage),
            weekCache: weekCache,
            shoppingCache: shoppingCache,
            householdSnapshotStore: snapshots
        )
        return ColdStart(model: model, storage: storage, auth: auth, weekCache: weekCache, shoppingCache: shoppingCache, snapshots: snapshots, directory: directory)
    }

    private func validSession() -> AuthSession {
        AuthSession(accessToken: AuthTestTokens.jwt(subject: Self.userID), refreshToken: "refresh", userID: Self.userID)
    }

    private func expiredSession() -> AuthSession {
        AuthSession(accessToken: AuthTestTokens.jwt(subject: Self.userID, expiresIn: -120), refreshToken: "refresh", userID: Self.userID)
    }

    @Test func restoringTheCachedCoreReaderShowsTheWeekAndListWithoutAnyNetwork() {
        let cold = makeColdStart(session: validSession())
        defer { try? FileManager.default.removeItem(at: cold.directory) }
        cold.model.authSessionStore.restoreSessionWithoutWaiting()

        cold.model.restoreCachedCoreReader()

        #expect(cold.model.householdStore.activeHousehold == Self.household)
        #expect(cold.model.weekStore.dayRows.first?.mealTitle == "Cachad rätt 0")
        #expect(cold.model.shoppingListStore.groups.flatMap(\.items).map(\.label) == ["Mjölk"])
        #expect(cold.model.weekStore.isShowingRestoredWeek(WeekCalendar.currentWeekStartDate()))
        #expect(cold.model.shoppingListStore.isShowingRestoredList)
    }

    @Test func coldStartWithAnUnreachableAPIKeepsShowingTheCachedWeekAndList() async {
        let cold = makeColdStart(session: validSession())
        defer { try? FileManager.default.removeItem(at: cold.directory) }

        await cold.model.restoreSession()

        #expect(cold.model.authSessionStore.isSignedIn)
        #expect(cold.model.householdStore.activeHousehold == Self.household)
        #expect(cold.model.weekStore.dayRows.first?.mealTitle == "Cachad rätt 0")
        #expect(cold.model.weekStore.errorMessage == nil)
        #expect(cold.model.shoppingListStore.groups.flatMap(\.items).map(\.label) == ["Mjölk"])
        #expect(cold.model.shoppingListStore.errorMessage == nil)
        // The household failed to load, but that must not hide the cached content.
        #expect(cold.model.householdStore.errorMessage != nil)
        #expect(cold.model.weekStore.isShowingRestoredWeek(WeekCalendar.currentWeekStartDate()))
        #expect(cold.model.shoppingListStore.isShowingRestoredList)
    }

    @Test func coldStartWithAnExpiredButRefreshableSessionStillShowsTheCache() async {
        let cold = makeColdStart(session: expiredSession())
        defer { try? FileManager.default.removeItem(at: cold.directory) }
        cold.auth.refreshResult = .success(validSession())

        await cold.model.restoreSession()

        #expect(cold.auth.refreshTokens == ["refresh"])
        #expect(cold.model.authSessionStore.isSignedIn)
        #expect(cold.model.weekStore.dayRows.first?.mealTitle == "Cachad rätt 0")
    }

    @Test func coldStartWithARejectedSessionSignsOutAndClearsEverything() async {
        let cold = makeColdStart(session: expiredSession())
        defer { try? FileManager.default.removeItem(at: cold.directory) }
        cold.auth.refreshResult = .failure(.invalidCredentials)

        await cold.model.restoreSession()

        #expect(!cold.model.authSessionStore.isSignedIn)
        #expect(cold.storage.session == nil)
        #expect(cold.model.householdStore.activeHousehold == nil)
        let week = WeekCalendar.currentWeekStartDate()
        let scope = Self.scope(language: CacheScope.currentLanguage)
        #expect(cold.weekCache.loadWeek(scope: scope, weekStartDate: week) == nil)
        #expect(cold.shoppingCache.loadList(scope: scope, weekStartDate: week) == nil)
        #expect(cold.snapshots.load(userID: Self.userID) == nil)
    }

    @Test func coldStartWithoutASavedSessionShowsNothingCached() async {
        let cold = makeColdStart(session: nil)
        defer { try? FileManager.default.removeItem(at: cold.directory) }

        await cold.model.restoreSession()

        #expect(!cold.model.authSessionStore.isSignedIn)
        #expect(cold.model.householdStore.activeHousehold == nil)
        #expect(cold.model.weekStore.dayRows.isEmpty)
    }

    @Test func coldStartWithoutARememberedHouseholdShowsNothingCached() {
        let cold = makeColdStart(session: validSession(), seedSnapshot: false)
        defer { try? FileManager.default.removeItem(at: cold.directory) }
        cold.model.authSessionStore.restoreSessionWithoutWaiting()

        cold.model.restoreCachedCoreReader()

        #expect(cold.model.householdStore.activeHousehold == nil)
        #expect(cold.model.weekStore.dayRows.isEmpty)
    }

    @Test func aCacheWrittenInAnotherLanguageIsNotShownOnColdStart() {
        let cold = makeColdStart(session: validSession(), seedCaches: false)
        defer { try? FileManager.default.removeItem(at: cold.directory) }
        let other = CacheScope.currentLanguage == "sv" ? "en" : "sv"
        cold.weekCache.saveWeek(Self.weekSummary(), scope: Self.scope(language: other))
        cold.model.authSessionStore.restoreSessionWithoutWaiting()

        cold.model.restoreCachedCoreReader()

        #expect(cold.model.householdStore.activeHousehold == Self.household)
        #expect(cold.model.weekStore.dayRows.isEmpty)
    }
}
