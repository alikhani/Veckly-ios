import SwiftUI

enum OnboardingStep: Hashable {
    case planningDays
    case goToDish
    case priorities
    case avoidIngredients
}

struct OnboardingFlowView: View {
    @State private var adults: Int = 1
    @State private var children: Int = 0
    @State private var selectedDays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    @State private var goToDishTitle = ""
    @State private var selectedPriorities: Set<HouseholdPriority> = []
    @State private var avoidIngredients: [String] = []
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
                        selectedDays: $selectedDays,
                        onContinue: { path.append(.goToDish) }
                    )
                case .goToDish:
                    OnboardingGoToDishView(
                        goToDishTitle: $goToDishTitle,
                        onContinue: { path.append(.priorities) }
                    )
                case .priorities:
                    OnboardingPrioritiesView(
                        selectedPriorities: $selectedPriorities,
                        onContinue: { path.append(.avoidIngredients) }
                    )
                case .avoidIngredients:
                    OnboardingAvoidIngredientsView(
                        adults: $adults,
                        children: $children,
                        selectedDays: $selectedDays,
                        goToDishTitle: $goToDishTitle,
                        selectedPriorities: $selectedPriorities,
                        avoidIngredients: $avoidIngredients
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
                    Text("onboarding.size.title")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    Text("onboarding.size.subtitle")
                        .font(.body)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VecklyCard {
                    VStack(spacing: 0) {
                        Stepper(L10n.format("household.adultsCount", adults), value: $adults, in: 1...20)
                            .foregroundStyle(VecklyDesign.Colors.inkDeep)
                            .padding(.vertical, 4)
                        Divider()
                        Stepper(L10n.format("household.childrenCount", children), value: $children, in: 0...20)
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
            Button("onboarding.continue", action: onContinue)
                .buttonStyle(VecklyPrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(VecklyDesign.Colors.canvas)
        }
    }
}

// MARK: - Screen 2

private struct OnboardingPlanningDaysView: View {
    @Binding var selectedDays: Set<Weekday>
    let onContinue: () -> Void

    private let row1: [Weekday] = [.monday, .tuesday, .wednesday, .thursday]
    private let row2: [Weekday] = [.friday, .saturday, .sunday]

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                brandHeader

                VStack(alignment: .leading, spacing: 8) {
                    Text("onboarding.days.title")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    Text("onboarding.days.subtitle")
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
            Button("onboarding.continue", action: onContinue)
                .buttonStyle(VecklyPrimaryButtonStyle())
                .disabled(selectedDays.isEmpty)
                .padding(.horizontal, 24)
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
            Text(day.shortDisplayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : VecklyDesign.Colors.inkMid)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? VecklyDesign.Colors.hearthOrangePrimaryFill : Color("chipSurface"))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Screen 3

private struct OnboardingGoToDishView: View {
    @Binding var goToDishTitle: String
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                brandHeader

                VStack(alignment: .leading, spacing: 8) {
                    Text("onboarding.goToDish.title")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    Text("onboarding.goToDish.subtitle")
                        .font(.body)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VecklyCard {
                    TextField(L10n.string("onboarding.goToDish.placeholder"), text: $goToDishTitle)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .onSubmit(onContinue)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
        }
        .background(VecklyDesign.Colors.canvas)
        .navigationBarHidden(true)
        .safeAreaInset(edge: .bottom) {
            Button("onboarding.continue", action: onContinue)
                .buttonStyle(VecklyPrimaryButtonStyle())
                .disabled(goToDishTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(VecklyDesign.Colors.canvas)
        }
    }
}

// MARK: - Screen 4

private struct OnboardingPrioritiesView: View {
    @Binding var selectedPriorities: Set<HouseholdPriority>
    let onContinue: () -> Void

    private let maxSelected = 2

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                brandHeader

                VStack(alignment: .leading, spacing: 8) {
                    Text("onboarding.priorities.title")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    Text("onboarding.priorities.subtitle")
                        .font(.body)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(HouseholdPriority.allCases, id: \.self) { priority in
                        priorityRow(priority)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
        }
        .background(VecklyDesign.Colors.canvas)
        .navigationBarHidden(true)
        .safeAreaInset(edge: .bottom) {
            Button("onboarding.continue", action: onContinue)
                .buttonStyle(VecklyPrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(VecklyDesign.Colors.canvas)
        }
    }

    private func priorityRow(_ priority: HouseholdPriority) -> some View {
        let isSelected = selectedPriorities.contains(priority)
        return Button {
            if isSelected {
                selectedPriorities.remove(priority)
            } else if selectedPriorities.count < maxSelected {
                selectedPriorities.insert(priority)
            }
        } label: {
            HStack {
                Text(priority.label)
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? VecklyDesign.Colors.hearthOrangeFill : VecklyDesign.Colors.inkFaint)
            }
            .padding(14)
            .background(VecklyDesign.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isSelected && selectedPriorities.count >= maxSelected)
        .opacity(!isSelected && selectedPriorities.count >= maxSelected ? 0.55 : 1)
    }
}

// MARK: - Screen 5

private struct OnboardingAvoidIngredientsView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var adults: Int
    @Binding var children: Int
    @Binding var selectedDays: Set<Weekday>
    @Binding var goToDishTitle: String
    @Binding var selectedPriorities: Set<HouseholdPriority>
    @Binding var avoidIngredients: [String]

    @State private var newIngredient = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                brandHeader

                VStack(alignment: .leading, spacing: 8) {
                    Text("onboarding.avoid.title")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    Text("onboarding.avoid.subtitle")
                        .font(.body)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VecklyCard {
                    VStack(alignment: .leading, spacing: 12) {
                        if avoidIngredients.isEmpty {
                            Text("onboarding.avoid.empty")
                                .font(.subheadline)
                                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        } else {
                            ForEach(avoidIngredients, id: \.self) { ingredient in
                                HStack {
                                    Text(ingredient)
                                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                                    Spacer()
                                    Button {
                                        avoidIngredients.removeAll { $0 == ingredient }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(VecklyDesign.Colors.inkFaint)
                                    }
                                    .accessibilityLabel(L10n.string("common.remove"))
                                }
                            }
                        }

                        HStack {
                            TextField(L10n.string("onboarding.avoid.placeholder"), text: $newIngredient)
                                .submitLabel(.done)
                                .onSubmit(addIngredient)
                            Button("common.add", action: addIngredient)
                                .disabled(newIngredient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
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
                        .foregroundStyle(.red)
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
                        Text("onboarding.setupWeek")
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

    private func addIngredient() {
        let trimmed = newIngredient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !avoidIngredients.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            newIngredient = ""
            return
        }
        avoidIngredients.append(trimmed)
        newIngredient = ""
    }

    private func complete() async {
        guard let household = appModel.householdStore.activeHousehold else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let orderedDays = Weekday.allCases
            .filter { selectedDays.contains($0) }
            .map { HouseholdDaySelection(day: $0) }

        let outcome = await OnboardingCompletion.run(
            recipeStore: appModel.recipeStore,
            householdStore: appModel.householdStore,
            householdID: household.id,
            adults: adults,
            children: children,
            priorities: Array(selectedPriorities),
            avoidIngredients: avoidIngredients.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            selectedDays: orderedDays,
            goToDishTitle: goToDishTitle
        )

        switch outcome {
        case .success(let goToDishSaved):
            appModel.recordProductEvent(.onboardingCompleted, properties: [
                "adults": .int(adults),
                "children": .int(children),
                "selectedDays": .int(selectedDays.count),
                "priorities": .int(selectedPriorities.count),
                "avoidIngredients": .int(avoidIngredients.count),
                "goToDishSaved": .bool(goToDishSaved)
            ])
            // Profile is now non-nil → needsOnboarding becomes false → cover dismisses automatically
            // No week generation here — user will choose to generate or add meals manually
        case .goToDishSaveFailed:
            errorMessage = L10n.string("onboarding.goToDishSaveError")
        case .profileSaveFailed:
            errorMessage = L10n.string("onboarding.saveError")
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
