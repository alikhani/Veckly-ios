import SwiftUI
import WidgetKit

private let appGroupID = "group.com.nimaalikhani.Veckly"
private let storageKey = "widget.snapshot.v1"

private struct Meal: Codable, Hashable {
    let date: String
    let title: String
    let minutes: Int?
    let recipeID: String

    var deepLink: URL? {
        var components = URLComponents()
        components.scheme = "veckly"
        components.host = "meal"
        components.queryItems = [
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "recipe", value: recipeID),
        ]
        return components.url
    }
}

private struct Snapshot: Codable, Hashable {
    static let staleInterval: TimeInterval = 12 * 60 * 60

    let updatedAt: Date
    let meals: [Meal]
    let shoppingRemainingCount: Int

    func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(updatedAt) > Self.staleInterval
    }
}

private struct Entry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?

    var currentSnapshot: Snapshot? {
        guard let snapshot, !snapshot.isStale(at: date) else { return nil }
        return snapshot
    }
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: Snapshot(
            updatedAt: Date(),
            meals: [Meal(date: "2026-10-01", title: "Tomato pasta", minutes: 25, recipeID: "preview")],
            shoppingRemainingCount: 8
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = loadEntry()
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: entry.date) ?? entry.date)
        let staleDate = entry.snapshot.map { $0.updatedAt.addingTimeInterval(Snapshot.staleInterval) }
        let refreshDate = [midnight, staleDate].compactMap { $0 }.filter { $0 > entry.date }.min()
            ?? entry.date.addingTimeInterval(60 * 60)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func loadEntry() -> Entry {
        let data = UserDefaults(suiteName: appGroupID)?.data(forKey: storageKey)
        let snapshot = data.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        return Entry(date: Date(), snapshot: snapshot)
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
            if let snapshot = entry.currentSnapshot {
                content(snapshot)
            } else {
                unavailable
            }
        }
        .containerBackground(WidgetStyle.canvas, for: .widget)
    }

    @ViewBuilder
    private func content(_ snapshot: Snapshot) -> some View {
        let meals = Array(snapshot.meals.prefix(family == .systemSmall ? 1 : 3))
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
                    Link(destination: meal.deepLink ?? URL(string: "veckly://")!) {
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
                    }
                    .privacySensitive()
                }
            }
            Spacer(minLength: 0)
        }
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
        Link(destination: URL(string: "veckly://shopping")!) {
            VStack(alignment: .leading, spacing: 8) {
                Label("widget.shopping.title", systemImage: "checklist")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetStyle.orange)
                if let count = entry.currentSnapshot?.shoppingRemainingCount {
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
        }
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
