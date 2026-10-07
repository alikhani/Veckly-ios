import SwiftUI
import WidgetKit

// Snapshot model and timeline rules live in Veckly/WidgetSnapshot.swift,
// shared with the app so they're unit-tested in VecklyTests.

private struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    var dinnerState: WidgetDinnerState {
        WidgetTimeline.dinnerState(for: snapshot, at: date)
    }

    var shoppingRemainingCount: Int? {
        guard let snapshot, !snapshot.isStale(at: date) else { return nil }
        return snapshot.shoppingRemainingCount
    }
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: WidgetSnapshot(
            updatedAt: Date(),
            meals: [WidgetMealSnapshot(
                date: WidgetDay.string(from: Date()),
                title: "Tomato pasta",
                minutes: 25,
                recipeID: "preview"
            )],
            shoppingRemainingCount: 8
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Entry(date: Date(), snapshot: loadSnapshot()))
    }

    /// One entry per local midnight so yesterday's dinner rolls off without
    /// the app being opened; reload once the last entry is reached.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snapshot = loadSnapshot()
        let entries = WidgetTimeline.entryDates(for: snapshot, now: Date())
            .map { Entry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func loadSnapshot() -> WidgetSnapshot? {
        let data = UserDefaults(suiteName: WidgetSnapshot.appGroupID)?.data(forKey: WidgetSnapshot.storageKey)
        return data.flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
    }
}

private enum WidgetStyle {
    static let orange = Color(red: 228 / 255, green: 87 / 255, blue: 46 / 255)
    static let ink = Color(red: 42 / 255, green: 38 / 255, blue: 34 / 255)
    static let canvas = Color(red: 249 / 255, green: 246 / 255, blue: 241 / 255)
}

private struct DinnerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        Group {
            switch entry.dinnerState {
            case .meals(let meals):
                content(meals)
            case .nothingPlanned:
                content([])
            case .needsUpdate:
                unavailable
            }
        }
        .widgetURL(entry.dinnerState.widgetURL)
        .containerBackground(WidgetStyle.canvas, for: .widget)
    }

    @ViewBuilder
    private func content(_ upcoming: [WidgetMealSnapshot]) -> some View {
        let meals = Array(upcoming.prefix(family == .systemSmall ? 1 : 3))
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            Label("widget.dinner.title", systemImage: "fork.knife")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetStyle.orange)
            if meals.isEmpty {
                Text("widget.dinner.empty")
                    .font(.headline)
                    .foregroundStyle(WidgetStyle.ink)
            } else {
                ForEach(meals, id: \.self) { meal in
                    if family == .systemSmall {
                        mealRow(meal)
                    } else {
                        Link(destination: meal.deepLink ?? URL(string: "veckly://")!) {
                            mealRow(meal)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func mealRow(_ meal: WidgetMealSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(dayLabel(for: meal.date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: family == .systemSmall ? nil : 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(meal.title)
                    .font(family == .systemSmall ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(WidgetStyle.ink)
                    .lineLimit(family == .systemSmall ? 2 : 1)
                if let minutes = meal.minutes {
                    Text("\(minutes) min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .privacySensitive()
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "fork.knife")
                .foregroundStyle(WidgetStyle.orange)
            Text("widget.update.title")
                .font(.headline)
                .foregroundStyle(WidgetStyle.ink)
            Text("widget.update.body")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func dayLabel(for value: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return value }
        if Calendar.current.isDateInToday(date) { return String(localized: "widget.day.today") }
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date).capitalized
    }
}

private struct ShoppingWidgetView: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("widget.shopping.title", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetStyle.orange)
            if let count = entry.shoppingRemainingCount {
                Text("\(count)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(WidgetStyle.ink)
                Text(count == 1 ? "widget.shopping.one" : "widget.shopping.other")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("widget.update.title")
                    .font(.headline)
                    .foregroundStyle(WidgetStyle.ink)
                Text("widget.update.body")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        // Small-only widget: `Link` is ignored in `.systemSmall`.
        .widgetURL(WidgetSnapshot.shoppingURL)
        .containerBackground(WidgetStyle.canvas, for: .widget)
    }
}

private struct DinnerWidget: Widget {
    let kind = "VecklyWidgets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            DinnerWidgetView(entry: entry)
        }
        .configurationDisplayName("widget.dinner.name")
        .description("widget.dinner.description")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct ShoppingWidget: Widget {
    let kind = "VecklyShoppingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ShoppingWidgetView(entry: entry)
        }
        .configurationDisplayName("widget.shopping.name")
        .description("widget.shopping.description")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct VecklyWidgetBundle: WidgetBundle {
    var body: some Widget {
        DinnerWidget()
        ShoppingWidget()
    }
}
