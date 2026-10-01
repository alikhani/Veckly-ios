import Testing
@testable import Veckly

@Suite("Week pulse")
struct WeekPulseTests {
    @Test func draftStartsFromCurrentMemberInput() {
        let member = WeekPulseMember(
            userID: "user",
            givenName: "Ava",
            familyName: nil,
            responded: true,
            isCurrentUser: true,
            awayDates: ["2026-10-07"],
            wishedMeal: "Tacos",
            simpleDate: "2026-10-08"
        )

        let draft = WeekPulseDraft(member: member)

        #expect(draft.awayDates == Set(["2026-10-07"]))
        #expect(draft.wishedMeal == "Tacos")
        #expect(draft.simpleDate == "2026-10-08")
    }

    @Test func pulseFindsCurrentMemberWithoutOpeningEveryResponse() {
        let current = WeekPulseMember(
            userID: "current", givenName: "Ava", familyName: nil,
            responded: false, isCurrentUser: true, awayDates: [], wishedMeal: nil, simpleDate: nil
        )
        let other = WeekPulseMember(
            userID: "other", givenName: "Bo", familyName: nil,
            responded: true, isCurrentUser: false, awayDates: [], wishedMeal: "Soup", simpleDate: nil
        )

        let pulse = WeekPulse(
            householdID: "household", weekStartDate: "2026-10-05",
            responseCount: 1, memberCount: 2, members: [other, current]
        )

        #expect(pulse.currentMember == current)
    }

    @Test func compromiseStatusesProduceDistinctExplanations() {
        let fulfilled = WeekPulseWishOutcome(userId: "a", givenName: "Ava", wishedMeal: "Tacos", status: .fulfilled)
        let unavailable = WeekPulseWishOutcome(userId: "b", givenName: "Bo", wishedMeal: "Ramen", status: .unavailable)
        let notSelected = WeekPulseWishOutcome(userId: "c", givenName: "Cia", wishedMeal: "Soup", status: .notSelected)

        #expect(fulfilled.sentence != unavailable.sentence)
        #expect(unavailable.sentence != notSelected.sentence)
        #expect(fulfilled.sentence.contains("Tacos"))
    }
}
