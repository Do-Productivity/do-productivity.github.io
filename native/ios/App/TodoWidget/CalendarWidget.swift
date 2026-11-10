//
//  The calendar, on the home screen and on the lock screen.
//
//  Separate widgets rather than one configurable one, deliberately. iOS
//  already has a picker — the gallery — and a person adding a widget is
//  choosing in that moment what they want it to say. Making them add a
//  generic widget and then go back into "Edit Widget" to pick between
//  tasks and meetings is a second decision for the same intention.
//
//  So: Today (what is next, from the calendar), Week (the shape of the
//  week), and the existing list widgets. Each in every size that makes
//  sense for what it says, including the lock screen accessories, where
//  the entire design problem is that you have one line and no colour.
//

import WidgetKit
import SwiftUI

// ── the calendar half of the payload ──────────────────────────────────────

struct CalItem: Codable, Hashable {
    let text: String
    let start: Double
    let end: Double
    let kind: String?        // "task" | "event" | "allday"
    let tint: String?

    var startsAt: Date { Date(timeIntervalSince1970: start / 1000) }
    var endsAt: Date { Date(timeIntervalSince1970: end / 1000) }
    var isAllDay: Bool { kind == "allday" }
    var isTask: Bool { kind == "task" }

    /// Running right now. The most useful thing a glance can tell you.
    var isNow: Bool {
        let n = Date()
        return startsAt <= n && endsAt > n && !isAllDay && start != end
    }
}

struct CalDay: Codable, Hashable {
    let at: Double
    let count: Int
    let items: [CalItem]

    var date: Date { Date(timeIntervalSince1970: at / 1000) }
}

// ── reading ───────────────────────────────────────────────────────────────

enum CalStore {
    /// Same group and same key as the list widgets: one payload, written
    /// once by the app, read by whichever widget happens to be on screen.
    static func load() -> (events: [CalItem], days: [CalDay], at: Date?) {
        guard let defaults = UserDefaults(suiteName: TodoStore.group),
              let raw = defaults.string(forKey: "CapacitorStorage.widgetData")
                     ?? defaults.string(forKey: "widgetData"),
              let data = raw.data(using: .utf8),
              let doc = try? JSONDecoder().decode(CalPayload.self, from: data)
        else { return ([], [], nil) }
        return (doc.events ?? [], doc.days ?? [],
                doc.at.map { Date(timeIntervalSince1970: $0 / 1000) })
    }

    private struct CalPayload: Codable {
        let at: Double?
        let events: [CalItem]?
        let days: [CalDay]?
    }

    /// The next thing today that has not finished, or the one running now.
    static func next(_ events: [CalItem]) -> CalItem? {
        let now = Date()
        if let live = events.first(where: { $0.isNow }) { return live }
        return events.first { $0.endsAt > now && !$0.isAllDay }
    }

    /// "in 25 min", "now", "9:30" — said the way a person would say it.
    static func when(_ item: CalItem) -> String {
        if item.isAllDay { return "all day" }
        if item.isNow { return "now" }
        let mins = Int(item.startsAt.timeIntervalSinceNow / 60)
        if mins < 1 { return "now" }
        if mins < 60 { return "in \(mins) min" }
        if mins < 120 { return "in an hour" }
        if mins < 60 * 8 { return "in \(Int(round(Double(mins) / 60))) hours" }
        return clock(item.startsAt)
    }

    static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        f.amSymbol = "am"; f.pmSymbol = "pm"
        let m = Calendar.current.component(.minute, from: d)
        f.dateFormat = m == 0 ? "ha" : "h:mma"
        return f.string(from: d).lowercased()
    }

    static func tint(_ name: String?) -> Color {
        switch name {
        case "red": return Color(red: 0.78, green: 0.33, blue: 0.24)
        case "blue": return Color(red: 0.24, green: 0.42, blue: 0.55)
        case "green": return Color(red: 0.29, green: 0.54, blue: 0.36)
        case "amber": return Color(red: 0.70, green: 0.44, blue: 0.12)
        case "teal": return Color(red: 0.21, green: 0.54, blue: 0.53)
        default: return Color(red: 0.45, green: 0.35, blue: 0.60)
        }
    }
}

// ── timeline ──────────────────────────────────────────────────────────────

struct CalEntry: TimelineEntry {
    let date: Date
    let events: [CalItem]
    let days: [CalDay]
    let stale: Bool
}

struct CalProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalEntry {
        CalEntry(date: Date(), events: [], days: [], stale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalEntry>) -> Void) {
        let e = entry()
        // A refresh on the hour is not enough: "in 25 min" is wrong within
        // a minute of being drawn. So the timeline carries an entry at each
        // boundary that changes what the widget says — the start and end of
        // everything left today — and iOS redraws at those exact moments
        // without the app running.
        var dates: [Date] = []
        let now = Date()
        for item in e.events {
            if item.startsAt > now { dates.append(item.startsAt) }
            if item.endsAt > now { dates.append(item.endsAt) }
        }
        dates.append(contentsOf: (1...8).map { now.addingTimeInterval(Double($0) * 900) })
        dates = Array(Set(dates)).sorted().prefix(24).map { $0 }

        let entries = [e] + dates.map {
            CalEntry(date: $0, events: e.events, days: e.days, stale: e.stale)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }

    private func entry() -> CalEntry {
        let (events, days, at) = CalStore.load()
        // Older than a day means the app has not run; say so rather than
        // presenting yesterday as today.
        let stale = at.map { Date().timeIntervalSince($0) > 86400 } ?? false
        return CalEntry(date: Date(), events: events, days: days, stale: stale)
    }
}

// ── the paper look ────────────────────────────────────────────────────────

private let paper = Color(red: 0.969, green: 0.953, blue: 0.914)
private let ink = Color(red: 0.169, green: 0.149, blue: 0.125)
private let inkSoft = Color(red: 0.42, green: 0.384, blue: 0.349)
private let rust = Color(red: 0.784, green: 0.333, blue: 0.239)

// ── today ─────────────────────────────────────────────────────────────────

struct CalTodayView: View {
    @Environment(\.widgetFamily) var family
    let entry: CalEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            // One line, no colour, no layout. All it can do is be the
            // sentence you would have wanted to read.
            if let n = CalStore.next(entry.events) {
                Text("\(CalStore.when(n)) · \(n.text)")
            } else {
                Text("Nothing left today")
            }

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.events.filter { $0.endsAt > Date() }.count)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("left").font(.system(size: 9))
                }
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if let n = CalStore.next(entry.events) {
                    Text(CalStore.when(n).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .widgetAccentable()
                    Text(n.text).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    if let after = upcoming().dropFirst().first {
                        Text("then \(CalStore.clock(after.startsAt)) · \(after.text)")
                            .font(.system(size: 10)).lineLimit(1).opacity(0.7)
                    }
                } else {
                    Text("CLEAR").font(.system(size: 10, weight: .bold)).widgetAccentable()
                    Text("Nothing left today").font(.system(size: 13, weight: .semibold))
                }
            }

        default:
            homeScreen
        }
    }

    private func upcoming() -> [CalItem] {
        let now = Date()
        return entry.events.filter { $0.endsAt > now }
    }

    private var homeScreen: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.custom("Iowan Old Style", size: 17).weight(.bold))
                    .foregroundColor(ink)
                Text(".").foregroundColor(rust)
                    .font(.custom("Iowan Old Style", size: 17).weight(.bold))
                Spacer()
                if entry.stale {
                    Text("old").font(.system(size: 9)).foregroundColor(rust)
                } else {
                    Text("\(upcoming().count) left").font(.system(size: 10)).foregroundColor(inkSoft)
                }
            }

            if upcoming().isEmpty {
                Text("Nothing left today.")
                    .font(.custom("Iowan Old Style", size: 14).italic())
                    .foregroundColor(inkSoft)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(upcoming().prefix(family == .systemSmall ? 2 : 5)), id: \.self) { it in
                        HStack(alignment: .top, spacing: 6) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(it.isNow ? rust : CalStore.tint(it.tint))
                                .frame(width: 3)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(it.isNow ? "now" : CalStore.clock(it.startsAt))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(it.isNow ? rust : inkSoft)
                                Text(it.text)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(ink)
                                    .lineLimit(family == .systemSmall ? 1 : 2)
                            }
                        }
                        .frame(height: family == .systemSmall ? 26 : 30, alignment: .top)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(13)
        .containerBackground(paper, for: .widget)
    }
}

// ── the week ──────────────────────────────────────────────────────────────

struct CalWeekView: View {
    @Environment(\.widgetFamily) var family
    let entry: CalEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(weekSummary())
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("THIS WEEK").font(.system(size: 10, weight: .bold)).widgetAccentable()
                HStack(spacing: 5) {
                    ForEach(entry.days.prefix(7), id: \.self) { d in
                        VStack(spacing: 1) {
                            Text(letter(d.date)).font(.system(size: 8, weight: .bold)).opacity(0.7)
                            Text("\(d.count)").font(.system(size: 12, weight: .bold))
                        }
                    }
                }
            }
        default:
            homeScreen
        }
    }

    private func weekSummary() -> String {
        let total = entry.days.reduce(0) { $0 + $1.count }
        return total == 0 ? "A clear week" : "\(total) this week"
    }

    private func letter(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f.string(from: d)
    }

    private var homeScreen: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").font(.custom("Iowan Old Style", size: 16).weight(.bold))
                    .foregroundColor(ink)
                Spacer()
                Text(weekSummary()).font(.system(size: 10)).foregroundColor(inkSoft)
            }

            // Seven columns of bars: the shape of the week at a glance,
            // which is the only thing a week ever needs to say from a home
            // screen. Numbers would be read one at a time.
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(entry.days.prefix(7), id: \.self) { d in
                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isToday(d.date) ? rust : CalStore.tint("teal").opacity(0.55))
                            .frame(height: max(3, min(CGFloat(d.count) * 9, 48)))
                        Text(letter(d.date))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(isToday(d.date) ? rust : inkSoft)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            if family == .systemLarge, let first = entry.days.first {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(first.items.prefix(4)), id: \.self) { it in
                        HStack(spacing: 6) {
                            Text(it.isAllDay ? "all day" : CalStore.clock(it.startsAt))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(inkSoft)
                                .frame(width: 46, alignment: .leading)
                            Text(it.text).font(.system(size: 12, weight: .semibold))
                                .foregroundColor(ink).lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(13)
        .containerBackground(paper, for: .widget)
    }

    private func isToday(_ d: Date) -> Bool { Calendar.current.isDateInToday(d) }
}

// ── the widgets ───────────────────────────────────────────────────────────

struct CalTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CalTodayWidget", provider: CalProvider()) { entry in
            CalTodayView(entry: entry)
        }
        .configurationDisplayName("Do. — what's next")
        .description("The next thing on your day, from your calendar and your lists.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryInline, .accessoryCircular, .accessoryRectangular
        ])
    }
}

struct CalWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CalWeekWidget", provider: CalProvider()) { entry in
            CalWeekView(entry: entry)
        }
        .configurationDisplayName("Do. — the week")
        .description("How full each day of the week is.")
        .supportedFamilies([
            .systemMedium, .systemLarge,
            .accessoryInline, .accessoryRectangular
        ])
    }
}
