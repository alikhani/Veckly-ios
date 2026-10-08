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
            shoppingCache: shoppingCache
        )
        let week = WeekCalendar.currentWeekStartDate()
        #expect(weekCache.loadWeek(scope: Self.scope(), weekStartDate: week) != nil)

        model.signOut()

        #expect(weekCache.loadWeek(scope: Self.scope(), weekStartDate: week) == nil)
        #expect(shoppingCache.loadList(scope: Self.scope(), weekStartDate: week) == nil)
    }
}
