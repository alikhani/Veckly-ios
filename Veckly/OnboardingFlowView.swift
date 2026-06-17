import SwiftUI

enum OnboardingStep: Hashable { case planningDays }

struct OnboardingFlowView: View {
    @State private var adults: Int = 1
    @State private var children: Int = 0
    @State private var selectedDays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    @State private var path: [OnboardingStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            OnboardingHouseholdSizeView(
                adults: $adults,
                children: $children,
                onContinue: { path.append(.planningDays) }
            )
            .navigationDestination(for: OnboardingStep.self) { step in
                switch step {
                case .planningDays:
                    OnboardingPlanningDaysView(
                        adults: $adults,
                        children: $children,
                        selectedDays: $selectedDays
                    )
                }
            }
        }
        .tint(VecklyDesign.Colors.inkMid)
        .interactiveDismissDisabled(true)
    }
}

// MARK: - Screen 1

private struct OnboardingHouseholdSizeView: View {
    @Binding var adults: Int
    @Binding var children: Int
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                brandHeader

                VStack(alignment: .leading, spacing: 8) {
                    Text("Who's eating this week?")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    Text("We'll size recipes to match your household.")
                        .font(.body)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VecklyCard {
                    VStack(spacing: 0) {
                        Stepper("Adults: \(adults)", value: $adults, in: 1...20)
                            .foregroundStyle(VecklyDesign.Colors.inkDeep)
                            .padding(.vertical, 4)
                        Divider()
                        Stepper("Children: \(children)", value: $children, in: 0...20)
                            .foregroundStyle(VecklyDesign.Colors.inkDeep)
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
        }
        .background(VecklyDesign.Colors.canvas)
        .navigationBarHidden(true)
        .safeAreaInset(edge: .bottom) {
            Button("Continue", action: onContinue)
                .buttonStyle(VecklyPrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(VecklyDesign.Colors.canvas)
        }
    }
}

// MARK: - Screen 2

private struct OnboardingPlanningDaysView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var adults: Int
    @Binding var children: Int
    @Binding var selectedDays: Set<Weekday>

    @State private var isSaving = false
    @State private var errorMessage: String?

    private let row1: [Weekday] = [.monday, .tuesday, .wednesday, .thursday]
    private let row2: [Weekday] = [.friday, .saturday, .sunday]

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                brandHeader

                VStack(alignment: .leading, spacing: 8) {
                    Text("Which days do you cook dinner?")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    Text("We'll only plan meals on these days.")
                        .font(.body)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(row1, id: \.self) { day in
                            dayChip(day)
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(row2, id: \.self) { day in
                            dayChip(day)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
        }
        .background(VecklyDesign.Colors.canvas)
        .navigationBarHidden(true)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(red: 0.80, green: 0.15, blue: 0.10))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                }

                Button {
                    Task { await complete() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    } else {
                        Text("Set up my week")
                    }
                }
                .buttonStyle(VecklyPrimaryButtonStyle())
                .disabled(selectedDays.isEmpty || isSaving)
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 16)
            .background(VecklyDesign.Colors.canvas)
        }
    }

    @ViewBuilder
    private func dayChip(_ day: Weekday) -> some View {
        let isSelected = selectedDays.contains(day)
        Button {
            if isSelected {
                selectedDays.remove(day)
            } else {
                selectedDays.insert(day)
            }
        } label: {
            Text(String(day.displayName.prefix(3)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : VecklyDesign.Colors.inkMid)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? VecklyDesign.Colors.hearthOrange : Color("chipSurface"))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func complete() async {
        guard let household = appModel.householdStore.activeHousehold else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let orderedDays = Weekday.allCases.filter { selectedDays.contains($0) }
        do {
            try await appModel.householdStore.saveProfile(
                householdID: household.id,
                adults: adults,
                children: children,
                priorities: [],
                avoidIngredients: [],
                selectedDays: orderedDays
            )
            // Profile is now non-nil → needsOnboarding becomes false → cover dismisses automatically
            // No week generation here — user will choose to generate or add meals manually
        } catch {
            errorMessage = "Could not save preferences. Check your connection and try again."
        }
    }
}

// MARK: - Shared brand header

private var brandHeader: some View {
    HStack(spacing: 10) {
        Image("VecklyMark")
            .resizable()
            .scaledToFit()
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

        Text("Veckly")
            .font(VecklyDesign.Typography.displayHeading(size: 24))
            .foregroundStyle(VecklyDesign.Colors.inkDeep)
    }
    .frame(maxWidth: .infinity, alignment: .center)
}
