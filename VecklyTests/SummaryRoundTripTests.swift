import Foundation
import Testing
@testable import Veckly

/// The week and shopping-list summaries are persisted to disk as JSON, so
/// every field must survive encode -> decode unchanged.
struct SummaryRoundTripTests {
    static let recipe = WeekSummaryRecipe(
        id: "22222222-2222-2222-2222-222222222222",
        title: "Pasta med tomatsås",
        description: "Snabb vardagspasta",
        servings: 4,
        prepTimeMinutes: 10,
        cookTimeMinutes: 20,
        tags: ["weekday", "kid-friendly"]
    )

    static let weekSummary = WeekSummary(
        household: SummaryHousehold(id: "11111111-1111-1111-1111-111111111111", name: "Familjen"),
        weekStartDate: "2026-10-05",
        updatedAt: "2026-10-06T08:15:30.123Z",
        explanations: [
            .weekContext(date: "2026-10-05", recipeTitle: "Pasta med tomatsås"),
            .leftoverChain(recipeTitle: "Gryta", cookDate: "2026-10-06", coveredDates: ["2026-10-07", "2026-10-08"]),
            .sharedIngredient(ingredient: "lök", dinnerCount: 3),
            .pantryCoverage(ingredients: ["ris", "pasta"]),
        ],
        pulse: WeekPulseOutcome(
            responseCount: 2,
            memberCount: 3,
            wishes: [
                WeekPulseWishOutcome(userId: "u1", givenName: "Alva", wishedMeal: "Tacos", status: .fulfilled),
                WeekPulseWishOutcome(userId: "u2", givenName: nil, wishedMeal: "Pizza", status: .unavailable),
                WeekPulseWishOutcome(userId: "u3", givenName: "Ola", wishedMeal: "Soppa", status: .notSelected),
            ]
        ),
        days: [
            WeekSummaryDay(
                dayOfWeek: .monday,
                date: "2026-10-05",
                state: .planned,
                isLocked: true,
                recipe: recipe,
                reason: .likedBefore,
                confidence: .low,
                streakWeeks: 3,
                portionSuggestion: PortionSuggestion(direction: .more, suggestedServings: 5, evidenceCount: 3, matchingCount: 2)
            ),
            WeekSummaryDay(dayOfWeek: .tuesday, date: "2026-10-06", state: .skipped, recipe: nil),
            WeekSummaryDay(dayOfWeek: .wednesday, date: "2026-10-07", state: .empty, recipe: nil),
            WeekSummaryDay(
                dayOfWeek: .thursday,
                date: "2026-10-08",
                state: .planned,
                recipe: recipe,
                reason: .pantryCoverage,
                confidence: .ok,
                portionSuggestion: PortionSuggestion(direction: .less, suggestedServings: 3, evidenceCount: 4, matchingCount: 4)
            ),
        ]
    )

    static let shoppingSummary = ShoppingListSummary(
        household: SummaryHousehold(id: "11111111-1111-1111-1111-111111111111", name: "Familjen"),
        weekStartDate: "2026-10-05",
        updatedAt: "2026-10-06T09:00:00.000Z",
        groups: [
            ShoppingListGroup(category: "Produce", items: [
                ShoppingListItem(itemKey: "produce:lök:st", label: "lök", amount: "2", unit: "st", checked: true),
                ShoppingListItem(itemKey: "produce:persilja:", label: "persilja", amount: nil, unit: nil, checked: false),
            ]),
            ShoppingListGroup(category: "Other", items: [
                ShoppingListItem(itemKey: "custom:abc", label: "Diskmedel", amount: nil, unit: nil, checked: false, isCustom: true),
            ]),
        ]
    )

    @Test func weekSummaryRoundTrips() throws {
        let data = try JSONEncoder().encode(Self.weekSummary)
        #expect(try JSONDecoder().decode(WeekSummary.self, from: data) == Self.weekSummary)
    }

    @Test func everyWeekExplanationKindRoundTrips() throws {
        for explanation in Self.weekSummary.explanations {
            let data = try JSONEncoder().encode(explanation)
            #expect(try JSONDecoder().decode(WeekExplanation.self, from: data) == explanation)
        }
    }

    @Test func shoppingListSummaryRoundTrips() throws {
        let data = try JSONEncoder().encode(Self.shoppingSummary)
        #expect(try JSONDecoder().decode(ShoppingListSummary.self, from: data) == Self.shoppingSummary)
    }

    @Test func householdRoundTrips() throws {
        let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Familjen", role: .member)
        let data = try JSONEncoder().encode(household)
        #expect(try JSONDecoder().decode(Household.self, from: data) == household)
    }

    @Test func aWeekSummaryWithoutOptionalFieldsRoundTrips() throws {
        let minimal = WeekSummary(
            household: SummaryHousehold(id: "h", name: "n"),
            weekStartDate: "2026-10-05",
            updatedAt: nil,
            days: []
        )
        let data = try JSONEncoder().encode(minimal)
        #expect(try JSONDecoder().decode(WeekSummary.self, from: data) == minimal)
    }
}
