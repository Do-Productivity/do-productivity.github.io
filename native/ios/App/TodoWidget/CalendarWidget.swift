//
//  The calendar, on the home screen and on the lock screen.
//
//  Separate widgets rather than one configurable one, deliberately. iOS
//  already has a picker — the gallery — and a person adding a widget is
//  choosing in that moment what they want it to say. Making them add a
//  generic widget and then go back into "Edit Widget" to pick between
//  tasks and meetings is a second decision for the same intention.
//
//  So: Today (the day's events, soonest first), Week (the shape of the
//  week as bars), Agenda (the week written out, day by day), and the
//  existing list widgets. Each in every size that makes sense for what it
//  says, including the lock screen accessories, where the entire design
//  problem is that you have a few lines and no colour.
//
//  Two rules the first version of this file broke, both of which produced
//  a lock screen that said "Nothing left today" on a full day:
//
//  1. A view never asks what time it is. WidgetKit draws every entry of a
//     timeline in advance, so Date() inside a view is the moment of
//     drawing, not the moment of showing. Everything here is worked out
//     from entry.date.
//
//  2. "Today" is looked up, not assumed. The app writes seven days at a
//     time and may not run again until Thursday; the first day in the
//     payload is the day it was written, which stops being today at
//     midnight. The day is found by date, every time.
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

    /// Running at that moment. The most useful thing a glance can tell you.
    func isNow(at now: Date) -> Bool {
        !isAllDay && !isTask && start != end && startsAt <= now && endsAt > now
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

    /// Everything the payload knows about the day `now` falls in, or nil
    /// when it knows nothing about that day at all — which is a different
    /// thing from knowing the day is empty, and is said differently.
    static func items(on now: Date, in entry: CalEntry) -> [CalItem]? {
        let cal = Calendar.current
        if let day = entry.days.first(where: { cal.isDate($0.date, inSameDayAs: now) }) {
            return day.items
        }
        // An older build of the app wrote today's list without the week.
        if let at = entry.at, cal.isDate(at, inSameDayAs: now) { return entry.events }
        return nil
    }

    /// What is still ahead of you at `now`, in the order you would want
    /// to be told: what is happening, then what is coming, then the tasks
    /// whose time has passed but which are still open, then anything that
    /// simply belongs to the day.
    ///
    /// All-day events are in here on purpose. Leaving them out is how a
    /// day whose only entry was a public holiday or a day's leave came
    /// out as "Nothing left today".
    static func left(_ items: [CalItem], at now: Date) -> [CalItem] {
        var running: [CalItem] = [], ahead: [CalItem] = []
        var due: [CalItem] = [], allDay: [CalItem] = []
        for it in items {
            if it.isAllDay { allDay.append(it) }
            else if it.isTask {
                if it.startsAt > now { ahead.append(it) } else { due.append(it) }
            }
            else if it.isNow(at: now) { running.append(it) }
            else if it.startsAt > now { ahead.append(it) }
        }
        ahead.sort { $0.start < $1.start }
        return running + ahead + due + allDay
    }

    /// The days from today onward, at most seven. A payload written on
    /// Monday and read on Wednesday still has Wednesday to Sunday in it.
    static func week(_ entry: CalEntry) -> [CalDay] {
        let from = Calendar.current.startOfDay(for: entry.date)
        return Array(entry.days.filter { $0.date >= from }
                               .sorted { $0.at < $1.at }
                               .prefix(7))
    }

    /// The word that goes in front of a title. Clock times, not "in 25
    /// min": a relative time is wrong a minute after it is drawn, and a
    /// lock screen is drawn long before it is read.
    static func label(_ it: CalItem, at now: Date) -> String {
        if it.isAllDay { return "all day" }
        if it.isTask {
            let c = Calendar.current.dateComponents([.hour, .minute], from: it.startsAt)
            if c.hour == 0 && c.minute == 0 { return "to do" }
            return it.startsAt <= now ? "due" : clock(it.startsAt)
        }
        return it.isNow(at: now) ? "now" : clock(it.startsAt)
    }

    /// "9am", "10:30am" — or "09:00", "15:00" on a phone set to the
    /// 24-hour clock. The first version asked for "ha" and let the system
    /// reinterpret it, which on a 24-hour phone printed a bare "09" or
    /// "15": a number, not a time. So the phone's preference is read once
    /// and the pattern is then applied exactly as written.
    static func clock(_ d: Date, twelveHour: Bool? = nil) -> String {
        let twelve = twelveHour ??
            (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current) ?? "h a")
                .contains("a")
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        guard twelve else {
            f.dateFormat = "HH:mm"
            return f.string(from: d)
        }
        f.amSymbol = "am"; f.pmSymbol = "pm"
        let m = Calendar.current.component(.minute, from: d)
        f.dateFormat = m == 0 ? "ha" : "h:mma"
        return f.string(from: d).lowercased()
    }

    /// How wide the time column has to be for these items: as wide as
    /// the longest label and no wider. "09:00" needs two-thirds of what
    /// "10:30am" does, and on a lock screen that difference is two more
    /// letters of every title.
    static func timeWidth(_ items: [CalItem], at now: Date, perChar: CGFloat) -> CGFloat {
        let longest = items.map { label($0, at: now).count }.max() ?? 5
        return max(4, CGFloat(longest)) * perChar + 2
    }

    /// Where to break a run of days into two columns so that neither is
    /// much taller than the other. Splitting down the middle by count put
    /// a busy Monday-to-Thursday beside an empty weekend: one column
    /// cutting events off, the other half blank.
    static func split(_ wants: [Int], head: CGFloat, line: CGFloat, gap: CGFloat) -> Int {
        guard wants.count > 1 else { return wants.count }
        func tall(_ part: ArraySlice<Int>) -> CGFloat {
            CGFloat(part.count) * head + CGFloat(part.reduce(0, +)) * line
                + CGFloat(max(0, part.count - 1)) * gap
        }
        var best = 1, bestHeight = CGFloat.greatestFiniteMagnitude
        for k in 1..<wants.count {
            let h = max(tall(wants[..<k]), tall(wants[k...]))
            if h < bestHeight { bestHeight = h; best = k }
        }
        return best
    }

    static func format(_ d: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.dateFormat = pattern
        return f.string(from: d)
    }

    /// Hand out `budget` lines among days that each want `counts[i]`.
    /// One each, round and round, so a heavy Monday cannot leave Thursday
    /// with a heading and nothing under it.
    static func share(_ counts: [Int], budget: Int) -> [Int] {
        var take = Array(repeating: 0, count: counts.count)
        var left = budget
        var moved = true
        while left > 0 && moved {
            moved = false
            for i in counts.indices where left > 0 && take[i] < counts[i] {
                take[i] += 1; left -= 1; moved = true
            }
        }
        return take
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
    let at: Date?

    /// What is left of the day this entry will be shown on; nil when the
    /// app has not told the widget anything about that day.
    var today: [CalItem]? {
        CalStore.items(on: date, in: self).map { CalStore.left($0, at: date) }
    }
    /// Whether the day had anything in it at all, finished or not.
    var hadAnything: Bool { !(CalStore.items(on: date, in: self) ?? []).isEmpty }
    /// More than a day since the app last wrote. Still shown — a meeting
    /// put in the diary last week is still on — but marked, because one
    /// added since will be missing.
    var aged: Bool { at.map { date.timeIntervalSince($0) > 86400 } ?? false }

    func at(_ when: Date) -> CalEntry {
        CalEntry(date: when, events: events, days: days, at: at)
    }
}

struct CalProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalEntry {
        CalEntry(date: Date(), events: [], days: [], at: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (CalEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalEntry>) -> Void) {
        let e = entry()
        let now = e.date
        let cal = Calendar.current
        // One entry for every moment that changes what the widget says:
        // each start and each end of what is left today and tomorrow, and
        // midnight, when "today" becomes a different day. iOS swaps them
        // in at those moments without the app, or this code, running.
        var dates = Set<Date>()
        let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))
            ?? now.addingTimeInterval(86400)
        dates.insert(midnight)
        for day in [now, midnight] {
            for item in CalStore.items(on: day, in: e) ?? [] where !item.isAllDay {
                if item.startsAt > now { dates.insert(item.startsAt) }
                if item.endsAt > now { dates.insert(item.endsAt) }
            }
        }
        let entries = [e] + dates.sorted().prefix(40).map { e.at($0) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }

    private func entry() -> CalEntry {
        let (events, days, at) = CalStore.load()
        return CalEntry(date: Date(), events: events, days: days, at: at)
    }
}

// ── the paper look ────────────────────────────────────────────────────────

private let paper = Color(red: 0.969, green: 0.953, blue: 0.914)
private let ink = Color(red: 0.169, green: 0.149, blue: 0.125)
private let inkSoft = Color(red: 0.42, green: 0.384, blue: 0.349)
private let rust = Color(red: 0.784, green: 0.333, blue: 0.239)

private func serif(_ size: CGFloat) -> Font { .custom("Iowan Old Style", size: size) }

/// One line of an agenda: a tinted bar, a time, a title.
private struct CalLine: View {
    let item: CalItem
    let now: Date
    var timeWidth: CGFloat = 38
    var timeSize: CGFloat = 8.5
    var titleSize: CGFloat = 10.5

    var body: some View {
        let live = item.isNow(at: now)
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(live ? rust : CalStore.tint(item.tint))
                .frame(width: 2.5, height: titleSize)
            Text(CalStore.label(item, at: now))
                .font(.system(size: timeSize, weight: .bold))
                .foregroundColor(live ? rust : inkSoft)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: timeWidth, alignment: .leading)
            Text(item.text)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundColor(ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

// ── today ─────────────────────────────────────────────────────────────────

struct CalTodayView: View {
    @Environment(\.widgetFamily) var family
    let entry: CalEntry

    var body: some View {
        // Every widget family must adopt a container background on iOS 17
        // and later — the lock-screen accessories included. Failing to is
        // not a build error, which is exactly why this got through: WidgetKit
        // silently replaces the view with a "Please adopt containerBackground"
        // notice. It was applied only to the home-screen branch, so the home
        // screen looked right and the lock screen showed the notice.
        //
        // On the lock screen the system draws its own backdrop and renders
        // the content in one tint, so there the correct background is none
        // at all — a paper rectangle would be a grey smear over the wallpaper.
        inner.containerBackground(for: .widget) { backdrop }
    }

    @ViewBuilder private var backdrop: some View {
        switch family {
        case .accessoryInline, .accessoryCircular, .accessoryRectangular:
            Color.clear
        default:
            paper
        }
    }

    private var now: Date { entry.date }

    /// Three different silences, and they are not the same news.
    private var quiet: (head: String, line: String) {
        if entry.today == nil { return ("DO.", "Open Do. to refresh") }
        return entry.hadAnything ? ("DONE", "Nothing left today") : ("CLEAR", "Nothing today")
    }

    /// The first thing tomorrow, for the evening when today has run out.
    private var tomorrow: CalItem? {
        guard let t = Calendar.current.date(byAdding: .day, value: 1, to: now),
              let items = CalStore.items(on: t, in: entry) else { return nil }
        return items.first { !$0.isAllDay } ?? items.first
    }

    @ViewBuilder private var inner: some View {
        let left = entry.today ?? []
        switch family {
        case .accessoryInline:
            // One line, no colour, no layout. All it can do is be the
            // sentence you would have wanted to read.
            if let n = left.first {
                Text("\(CalStore.label(n, at: now)) · \(n.text)")
            } else {
                Text(quiet.line)
            }

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(left.count)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("left").font(.system(size: 9))
                }
            }

        case .accessoryRectangular:
            Group {
                if left.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(quiet.head).font(.system(size: 10, weight: .bold)).widgetAccentable()
                        Text(quiet.line).font(.system(size: 13, weight: .semibold))
                        if entry.today != nil, let t = tomorrow {
                            Text("tomorrow \(CalStore.label(t, at: now)) · \(t.text)")
                                .font(.system(size: 10)).lineLimit(1).opacity(0.7)
                        }
                    }
                } else if left.count == 1, let only = left.first {
                    // One thing left: give it the room.
                    VStack(alignment: .leading, spacing: 1) {
                        Text(CalStore.label(only, at: now).uppercased())
                            .font(.system(size: 10, weight: .bold)).widgetAccentable()
                        Text(only.text).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    }
                } else {
                    // The day, as many lines of it as this phone has room
                    // for: four on the larger ones, three on the rest.
                    ViewThatFits(in: .vertical) {
                        lockRows(left, 4)
                        lockRows(left, 3)
                        lockRows(left, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

        default:
            homeScreen(left)
        }
    }

    private func lockRows(_ items: [CalItem], _ n: Int) -> some View {
        let shown = Array(items.prefix(n))
        let timeW = CalStore.timeWidth(shown, at: now, perChar: 6.2)
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, it in
                HStack(spacing: 4) {
                    Text(CalStore.label(it, at: now))
                        .font(.system(size: 10, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: timeW, alignment: .leading)
                        .widgetAccentable(i == 0)
                    Text(it.text)
                        .font(.system(size: 12, weight: i == 0 ? .bold : .medium))
                        .lineLimit(1)
                    if i == shown.count - 1 && items.count > shown.count {
                        Spacer(minLength: 2)
                        Text("+\(items.count - shown.count)")
                            .font(.system(size: 9, weight: .bold)).opacity(0.7)
                    }
                }
            }
        }
    }

    private func homeRow(_ it: CalItem, lines: Int) -> some View {
        let live = it.isNow(at: now)
        return HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(live ? rust : CalStore.tint(it.tint))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(CalStore.label(it, at: now))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(live ? rust : inkSoft)
                Text(it.text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ink)
                    .lineLimit(lines)
            }
            Spacer(minLength: 0)
        }
        .frame(height: lines == 1 ? 26 : 30, alignment: .top)
    }

    private func homeScreen(_ left: [CalItem]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                (Text("Today").foregroundColor(ink) + Text(".").foregroundColor(rust))
                    .font(serif(17).weight(.bold))
                Spacer()
                if entry.aged || entry.today == nil {
                    Text("open to refresh").font(.system(size: 9)).foregroundColor(rust)
                } else {
                    Text("\(left.count) left").font(.system(size: 10)).foregroundColor(inkSoft)
                }
            }

            if left.isEmpty {
                Text(quiet.line + ".").font(serif(14).italic()).foregroundColor(inkSoft)
                if entry.today != nil, let t = tomorrow {
                    Text("Tomorrow \(CalStore.label(t, at: now)) · \(t.text)")
                        .font(.system(size: 10)).foregroundColor(inkSoft).lineLimit(2)
                }
            } else if family == .systemMedium {
                // Medium is as short as small and twice as wide, so the
                // day goes in two columns of three rather than one of five
                // that ran off the bottom.
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<2, id: \.self) { col in
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(left.dropFirst(col * 3).prefix(3).enumerated()), id: \.offset) { _, it in
                                homeRow(it, lines: 1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(left.prefix(family == .systemSmall ? 3 : 8).enumerated()), id: \.offset) { _, it in
                        homeRow(it, lines: family == .systemSmall ? 1 : 2)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(13)
    }
}

// ── the week, as a shape ──────────────────────────────────────────────────

struct CalWeekView: View {
    @Environment(\.widgetFamily) var family
    let entry: CalEntry

    var body: some View {
        // See CalTodayView.body: every family adopts a container
        // background, and on the lock screen the right one is none.
        inner.containerBackground(for: .widget) { backdrop }
    }

    @ViewBuilder private var backdrop: some View {
        switch family {
        case .accessoryInline, .accessoryCircular, .accessoryRectangular:
            Color.clear
        default:
            paper
        }
    }

    private var days: [CalDay] { CalStore.week(entry) }

    @ViewBuilder private var inner: some View {
        switch family {
        case .accessoryInline:
            Text(weekSummary())
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("THIS WEEK").font(.system(size: 10, weight: .bold)).widgetAccentable()
                HStack(spacing: 5) {
                    ForEach(days, id: \.at) { d in
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
        if days.isEmpty { return "Open Do. to refresh" }
        let total = days.reduce(0) { $0 + $1.count }
        return total == 0 ? "A clear week" : "\(total) this week"
    }

    private func letter(_ d: Date) -> String { CalStore.format(d, "EEEEE") }

    private var homeScreen: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").font(serif(16).weight(.bold)).foregroundColor(ink)
                Spacer()
                Text(weekSummary()).font(.system(size: 10)).foregroundColor(inkSoft)
            }

            // Seven columns of bars: the shape of the week at a glance.
            // The agenda widget is the one that names things.
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(days, id: \.at) { d in
                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isToday(d.date) ? rust : CalStore.tint("teal").opacity(0.55))
                            .frame(height: max(3, min(CGFloat(d.count) * 9, 48)))
                        Text(letter(d.date))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(isToday(d.date) ? rust : inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)

            if family == .systemLarge, let left = entry.today, !left.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(left.prefix(4).enumerated()), id: \.offset) { _, it in
                        CalLine(item: it, now: entry.date, timeWidth: 46, timeSize: 9, titleSize: 12)
                    }
                }
            }
        }
        .padding(13)
    }

    private func isToday(_ d: Date) -> Bool {
        Calendar.current.isDate(d, inSameDayAs: entry.date)
    }
}

// ── the week, written out ─────────────────────────────────────────────────
//
//  The large home-screen widget: seven days, each with its events under
//  it. This is the "bigger one" — iOS has no lock-screen size above the
//  small rectangle, so a week that names its events lives here.
//
//  Two columns, because seven headings down one column leaves room for
//  about one event each, and a week you cannot read is the bars again
//  with more ink. The days stay in order and the break between the
//  columns goes wherever it leaves them most nearly the same height. The
//  lines there is room for are then dealt out one to each day in turn, so
//  no day is a heading with nothing under it while another shows nine;
//  whatever did not fit is counted beside the day.

struct CalAgendaView: View {
    let entry: CalEntry

    private let headH: CGFloat = 15
    private let lineH: CGFloat = 14
    private let gap: CGFloat = 5

    var body: some View {
        content.containerBackground(for: .widget) { paper }
    }

    private var now: Date { entry.date }

    private var content: some View {
        let days = CalStore.week(entry)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                (Text("The week").foregroundColor(ink) + Text(".").foregroundColor(rust))
                    .font(serif(16).weight(.bold))
                Spacer()
                if entry.aged {
                    Text("open to refresh").font(.system(size: 9)).foregroundColor(rust)
                } else if let a = days.first, let b = days.last {
                    Text("\(CalStore.format(a.date, "d MMM")) – \(CalStore.format(b.date, "d MMM"))")
                        .font(.system(size: 10)).foregroundColor(inkSoft)
                }
            }

            if days.isEmpty {
                Text("Open Do. to bring the week in.")
                    .font(serif(14).italic()).foregroundColor(inkSoft)
                Spacer(minLength: 0)
            } else {
                GeometryReader { geo in
                    let split = CalStore.split(days.map { visible($0).count },
                                               head: headH, line: lineH, gap: gap)
                    HStack(alignment: .top, spacing: 12) {
                        column(Array(days.prefix(split)), height: geo.size.height)
                        column(Array(days.dropFirst(split)), height: geo.size.height)
                    }
                }
            }
        }
        .padding(14)
    }

    /// Today shows what is left of it; every other day shows all of it.
    private func visible(_ day: CalDay) -> [CalItem] {
        Calendar.current.isDate(day.date, inSameDayAs: now)
            ? CalStore.left(day.items, at: now) : day.items
    }

    private func column(_ days: [CalDay], height: CGFloat) -> some View {
        let lists = days.map { visible($0) }
        let fixed = CGFloat(days.count) * headH + CGFloat(max(0, days.count - 1)) * gap
        let budget = max(0, Int((height - fixed) / lineH))
        let take = CalStore.share(lists.map { $0.count }, budget: budget)
        let shown = zip(lists, take).flatMap { $0.prefix($1) }
        let timeW = CalStore.timeWidth(shown, at: now, perChar: 5.2)
        return VStack(alignment: .leading, spacing: gap) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                block(day, lists[i], take[i], timeW)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func block(_ day: CalDay, _ list: [CalItem], _ take: Int, _ timeW: CGFloat) -> some View {
        let isToday = Calendar.current.isDate(day.date, inSameDayAs: now)
        // Not shown here, plus any the app left out of the payload.
        let more = list.count - take + max(0, day.count - day.items.count)
        let note = list.isEmpty ? (day.count > 0 ? "done" : "clear")
                                : (more > 0 ? "+\(more) more" : "")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(isToday ? "Today" : CalStore.format(day.date, "EEE d"))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(isToday ? rust : ink)
                if isToday {
                    Text(CalStore.format(day.date, "EEE d"))
                        .font(.system(size: 9)).foregroundColor(inkSoft)
                }
                Spacer(minLength: 2)
                Text(note).font(.system(size: 9)).foregroundColor(inkSoft)
            }
            .frame(height: headH)
            ForEach(Array(list.prefix(take).enumerated()), id: \.offset) { _, it in
                CalLine(item: it, now: now, timeWidth: timeW).frame(height: lineH)
            }
        }
    }
}

// ── the widgets ───────────────────────────────────────────────────────────

struct CalTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CalTodayWidget", provider: CalProvider()) { entry in
            CalTodayView(entry: entry)
        }
        .configurationDisplayName("Do. — today")
        .description("What is left of today, from your calendar and your lists.")
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

struct CalAgendaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CalAgendaWidget", provider: CalProvider()) { entry in
            CalAgendaView(entry: entry)
        }
        .configurationDisplayName("Do. — week agenda")
        .description("The next seven days, with every event and dated task under its day.")
        .supportedFamilies([.systemLarge])
    }
}
