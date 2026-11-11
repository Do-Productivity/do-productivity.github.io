//
//  Home screen widget for My To Do List.
//
//  Two data paths, on purpose:
//
//    1. the App Group (group.com.ahmedmohsen.todolist.shared), written by the app
//       through Capacitor Preferences. No network, no token, current the
//       moment the app saves.
//    2. the public sync feed, if the group is empty or unreadable. A free
//       Xcode signing team may refuse to register an App Group, and the
//       widget must not be dead weight if that happens. This is the same
//       feed the Scriptable widget read, so it is nothing newly exposed.
//
//  Capacitor Preferences stores under "CapacitorStorage.<key>", which is why
//  the group lookup tries that first.
//

import WidgetKit
import SwiftUI

// ── the shape the app writes ───────────────────────────────────────────────

struct TodoItem: Codable, Hashable {
    let text: String
    let due: Double?
}

struct TodoList: Codable, Hashable {
    let id: String
    let title: String
    let tint: String?
    let count: Int
    let items: [TodoItem]
}

struct TodoPayload: Codable {
    let build: String?
    let at: Double?
    let lists: [TodoList]
    let today: Int?
    let overdue: Int?
}

// ── the shape the sync feed has (fallback) ─────────────────────────────────

private struct FeedTask: Codable {
    let text: String?
    let due: Double?
    let done: Bool?
    let deleted: Bool?
}

private struct FeedList: Codable {
    let id: String?
    let title: String?
    let tint: String?
    let deleted: Bool?
}

private struct FeedDoc: Codable {
    let lists: [String: [FeedTask]]?
    let customLists: [FeedList]?
}

// ── loading ───────────────────────────────────────────────────────────────

enum TodoStore {
    static let group = "group.com.ahmedmohsen.todolist.shared"
    static let feed = URL(string:
        "https://gist.githubusercontent.com/ahmedmohsen18/" +
        "1f3e9c2d3186c395b62391c6b62f0358/raw/dia-todo.json")!

    static func fromGroup() -> TodoPayload? {
        guard let defaults = UserDefaults(suiteName: group) else { return nil }
        let raw = defaults.string(forKey: "widgetData")
            ?? defaults.string(forKey: "CapacitorStorage.widgetData")
        guard let json = raw, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TodoPayload.self, from: data)
    }

    static func fromFeed() async -> TodoPayload? {
        var request = URLRequest(url: feed)
        // the raw gist sets max-age=300; without this the widget can show a
        // five-minute-old list and look broken
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let doc = try? JSONDecoder().decode(FeedDoc.self, from: data),
              let raw = doc.lists else { return nil }

        var titles = ["personal": "Personal", "business": "Business"]
        for l in doc.customLists ?? [] where l.deleted != true {
            if let id = l.id, let t = l.title { titles[id] = t }
        }

        let now = Date().timeIntervalSince1970 * 1000
        var endOfDay = Calendar.current.startOfDay(for: Date())
        endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: endOfDay) ?? endOfDay
        let dayEnd = endOfDay.timeIntervalSince1970 * 1000

        var lists: [TodoList] = []
        var today = 0, overdue = 0
        let order = ["personal", "business"] +
            raw.keys.filter { $0 != "personal" && $0 != "business" }.sorted()

        for id in order {
            guard let tasks = raw[id] else { continue }
            let open = tasks.filter { $0.done != true && $0.deleted != true }
            for t in open {
                guard let due = t.due else { continue }
                if due < now { overdue += 1 } else if due <= dayEnd { today += 1 }
            }
            let sorted = open.sorted { a, b in
                if (a.due != nil) != (b.due != nil) { return a.due != nil }
                return (a.due ?? 0) < (b.due ?? 0)
            }
            lists.append(TodoList(
                id: id,
                title: titles[id] ?? id.capitalized,
                tint: nil,
                count: open.count,
                items: sorted.prefix(14).map { TodoItem(text: $0.text ?? "", due: $0.due) }
            ))
        }
        return TodoPayload(build: nil, at: now, lists: lists, today: today, overdue: overdue)
    }

    static func load() async -> (TodoPayload?, Bool) {
        if let local = fromGroup(), !local.lists.isEmpty { return (local, true) }
        return (await fromFeed(), false)
    }
}

// ── timeline ──────────────────────────────────────────────────────────────

struct TodoEntry: TimelineEntry {
    let date: Date
    let payload: TodoPayload?
    let fromGroup: Bool
    let listId: String?       // nil = every list
}

struct TodoProvider: TimelineProvider {
    let listId: String?

    func placeholder(in context: Context) -> TodoEntry {
        TodoEntry(date: Date(), payload: nil, fromGroup: true, listId: listId)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        Task {
            let (payload, local) = await TodoStore.load()
            completion(TodoEntry(date: Date(), payload: payload,
                                 fromGroup: local, listId: listId))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        Task {
            let (payload, local) = await TodoStore.load()
            let now = Date()
            var entries = [TodoEntry(date: now, payload: payload,
                                     fromGroup: local, listId: listId)]

            // Re-render as each of the next few due times passes, so a task
            // turns overdue on the home screen without waiting for a refresh
            // iOS may not grant for 15 minutes.
            let upcoming = (payload?.lists.flatMap { $0.items } ?? [])
                .compactMap { $0.due }
                .map { Date(timeIntervalSince1970: $0 / 1000) }
                .filter { $0 > now }
                .sorted()
                .prefix(4)
            for when in upcoming {
                entries.append(TodoEntry(date: when, payload: payload,
                                         fromGroup: local, listId: listId))
            }

            completion(Timeline(entries: entries,
                                policy: .after(now.addingTimeInterval(15 * 60))))
        }
    }
}

// ── look ──────────────────────────────────────────────────────────────────
//
// The paper, the ink, the rust and the serif are the calendar widgets' own
// (CalendarWidget.swift), so a lists widget beside a week widget reads as
// one set: a serif heading with a rust full stop, a colour bar down the
// side of every line, condensed semibold titles that wrap when there is
// room for them.

enum TodoLook {
    /// A list's colour. The named tints are the calendar's; a colour picked
    /// by hand arrives as "#rrggbb". The sync feed carries no tints at all,
    /// so the two built-in lists fall back to the colours the app gives them.
    static func tint(_ list: TodoList) -> Color {
        if let t = list.tint {
            if t.hasPrefix("#") { return hex(t) ?? CalStore.tint("amber") }
            return CalStore.tint(t)
        }
        switch list.id {
        case "personal": return CalStore.tint("red")
        case "business": return CalStore.tint("blue")
        default: return CalStore.tint("amber")
        }
    }

    static func hex(_ s: String) -> Color? {
        let digits = s.dropFirst()
        guard digits.count == 6, let v = UInt32(digits, radix: 16) else { return nil }
        var r = Double((v >> 16) & 0xff) / 255
        var g = Double((v >> 8) & 0xff) / 255
        var b = Double(v & 0xff) / 255
        // A pale colour would vanish on paper, and a list's heading is set
        // in it: bring it down to where it can still be read.
        let light = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if light > 0.5 { let k = 0.5 / light; r *= k; g *= k; b *= k }
        return Color(red: r, green: g, blue: b)
    }

    /// When a task is due, in as few characters as say it: a time today,
    /// "tmrw" and a time, a weekday inside the week, a date beyond it.
    static func due(_ ms: Double?, at now: Date) -> (text: String, late: Bool)? {
        guard let ms = ms else { return nil }
        let date = Date(timeIntervalSince1970: ms / 1000)
        let cal = Calendar.current
        let late = date < now
        if cal.isDate(date, inSameDayAs: now) { return (CalStore.clock(date), late) }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now),
                                      to: cal.startOfDay(for: date)).day ?? 0
        if days == 1 { return ("tmrw " + CalStore.clock(date), false) }
        if days > 1 && days < 7 { return (CalStore.format(date, "EEE d"), false) }
        return (CalStore.format(date, "d MMM"), late)
    }
}

/// One task: a bar in its list's colour (rust once it is overdue), the
/// title, and when it is due.
struct TaskLine: View {
    let item: TodoItem
    let tint: Color
    let now: Date
    var titleSize: CGFloat = 10.5
    /// How many lines the title may take. Above one, the row grows to fit
    /// and the colour bar runs the full height of the wrapped title.
    var lines: Int = 1

    var body: some View {
        let due = TodoLook.due(item.due, at: now)
        let late = due?.late ?? false
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(item.text)
                .font(.system(size: titleSize, weight: .semibold).width(.condensed))
                .foregroundColor(ink)
                .lineLimit(lines)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let due = due {
                Text(due.text)
                    .font(.system(size: titleSize - 2, weight: .bold))
                    .foregroundColor(late ? rust : inkSoft)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.leading, 6.5)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(late ? rust : tint)
                .frame(width: 2.5)
                .padding(.vertical, 1)
        }
    }
}

/// A run of tasks under one heading — or under none, when the widget's own
/// heading already says whose they are.
struct TodoBlock {
    let title: String?
    let tint: Color
    /// Everything open in it, shown or not.
    let count: Int
    let rows: [(item: TodoItem, tint: Color)]
}

/// A column of blocks and how many rows each one gets.
struct TodoColumn {
    let blocks: [TodoBlock]
    let take: [Int]
    var complete: Bool { zip(blocks, take).allSatisfy { $0.count == $1 } }
}

/// The two sizes of type. Compact is the week widget's own; roomy is for a
/// widget with so little in it that the small type would leave it half empty.
struct TodoType {
    let title: CGFloat
    let head: CGFloat
    let line: CGFloat
    let gap: CGFloat
    static let compact = TodoType(title: 10.5, head: 15, line: 14, gap: 5)
    static let roomy = TodoType(title: 12.5, head: 18, line: 17, gap: 7)
}

struct TodoWidgetView: View {
    var entry: TodoEntry
    @Environment(\.widgetFamily) private var family

    private var now: Date { entry.date }

    private var lists: [TodoList] {
        let all = entry.payload?.lists ?? []
        guard let want = entry.listId else { return all }
        return all.filter { $0.id == want }
    }

    /// Every open task in whatever this widget is scoped to, soonest first.
    private var flat: [TodoItem] { soonest(lists.flatMap { $0.items }) { $0 } }
    private var openCount: Int { lists.reduce(0) { $0 + $1.count } }

    /// Dated before undated, then by date; otherwise the order they came in.
    private func soonest<T>(_ all: [T], _ item: (T) -> TodoItem) -> [T] {
        all.enumerated().sorted { a, b in
            let x = item(a.element).due, y = item(b.element).due
            if (x != nil) != (y != nil) { return x != nil }
            if let x = x, let y = y, x != y { return x < y }
            return a.offset < b.offset
        }.map { $0.element }
    }

    /// Counted now, from the tasks themselves, so a task that turns overdue
    /// while the phone is in a pocket is counted as late without the app
    /// having to be opened.
    private var counts: (late: Int, today: Int) {
        var late = 0, today = 0
        for task in lists.flatMap({ $0.items }) {
            guard let ms = task.due else { continue }
            let date = Date(timeIntervalSince1970: ms / 1000)
            if date < now { late += 1 }
            else if Calendar.current.isDate(date, inSameDayAs: now) { today += 1 }
        }
        // A list sends its first few tasks only; the app's own count knows
        // about the overdue ones past that.
        if entry.listId == nil { late = max(late, entry.payload?.overdue ?? 0) }
        // …but never more late tasks than there are open ones: a count left
        // over from before the last one was ticked off must not sit beside
        // "Nothing open."
        return (min(late, openCount), today)
    }

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

    @ViewBuilder private var inner: some View {
        switch family {
        // ── The lock screen ──
        // No colour, no background of our own, and in the inline case no
        // layout at all: the system draws these in one tint over whatever
        // wallpaper is there. A design that assumes paper and rust would be
        // a grey smear. So these say the one true thing they have room for.
        case .accessoryInline:
            if let first = flat.first {
                Text("\(openCount) to do · \(first.text)")
            } else {
                Text("Nothing to do")
            }

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(openCount)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("to do").font(.system(size: 9))
                }
            }

        case .accessoryRectangular:
            lockScreen

        default:
            if entry.payload == nil {
                VStack(alignment: .leading, spacing: 7) {
                    heading("To do")
                    Text("Open Do. once to bring your lists in.")
                        .font(serif(14).italic()).foregroundColor(inkSoft)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(inset)
            } else {
                homeScreen
            }
        }
    }

    // ── the lock screen ──

    private var lockScreen: some View {
        let tasks = flat
        let late = counts.late
        // Fullest first: three tasks with their titles wrapped, then three
        // on a line each, then fewer. Short titles take one line whatever
        // they are allowed, so the first arrangement that fits is the one
        // that shows the most.
        let tries: [(rows: Int, lines: Int)] =
            [(3, 3), (3, 2), (3, 1), (2, 3), (2, 2), (2, 1), (1, 3)]
                .filter { $0.rows <= max(1, tasks.count) }
        return VStack(alignment: .leading, spacing: 1) {
            Text("\(openCount) TO DO" + (late > 0 ? " · \(late) LATE" : ""))
                .font(.system(size: 10, weight: .bold))
                .widgetAccentable()
            if tasks.isEmpty {
                Text("Nothing open").font(.system(size: 12, weight: .semibold))
            } else {
                ViewThatFits(in: .vertical) {
                    ForEach(Array(tries.enumerated()), id: \.offset) { _, t in
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(tasks.prefix(t.rows).enumerated()), id: \.offset) { _, task in
                                lockRow(task, lines: t.lines)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// When it is due and what it is, as one run of text so a long title
    /// wraps under the time rather than beside it.
    private func lockRow(_ task: TodoItem, lines: Int) -> some View {
        let due = TodoLook.due(task.due, at: now)
        let when = Text(due.map { $0.text + "\u{2002}" } ?? "")
            .font(.system(size: 10.5, weight: .heavy).width(.condensed))
        let what = Text(task.text)
            .font(.system(size: 12, weight: .semibold).width(.condensed))
        return (when + what)
            .lineLimit(lines)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    // ── the home screen ──

    /// The system already keeps the content off the widget's edge; this is
    /// the little more the larger sizes can afford.
    private var inset: CGFloat { family == .systemSmall ? 0 : 6 }

    private func heading(_ words: String) -> some View {
        (Text(words).foregroundColor(ink) + Text(".").foregroundColor(rust))
            .font(serif(family == .systemSmall ? 15 : 16).weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var header: some View {
        let (late, today) = counts
        let small = family == .systemSmall
        let title = entry.listId == nil ? "To do" : (lists.first?.title ?? "To do")
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            heading(title)
            Spacer(minLength: 4)
            if late > 0 {
                Text("\(late) late")
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(rust)
            }
            // The small one has room for one figure: the urgent one.
            if today > 0 && !(small && late > 0) {
                Text(late > 0 ? "· \(today) today" : "\(today) today")
                    .font(.system(size: 10)).foregroundColor(inkSoft)
            }
            if late == 0 && today == 0 && openCount > 0 {
                Text("\(openCount) open").font(.system(size: 10)).foregroundColor(inkSoft)
            }
        }
        .lineLimit(1)
    }

    /// What goes under the heading. Every list in the two larger sizes is a
    /// titled block per list, the dashboard's own shape. One list — or the
    /// small size, which has no room for headings — is a single run, each
    /// task still wearing its list's colour.
    private var blocks: [TodoBlock] {
        let open = lists.filter { !$0.items.isEmpty }
        if entry.listId != nil || family == .systemSmall || open.count == 1 {
            let rows = soonest(open.flatMap { l in
                l.items.map { (item: $0, tint: TodoLook.tint(l)) }
            }) { $0.item }
            return rows.isEmpty ? [] : [TodoBlock(title: nil, tint: ink, count: openCount, rows: rows)]
        }
        return open.map { l in
            let tint = TodoLook.tint(l)
            return TodoBlock(title: l.title, tint: tint, count: l.count,
                             rows: l.items.map { (item: $0, tint: tint) })
        }
    }

    private var homeScreen: some View {
        let all = blocks
        return VStack(alignment: .leading, spacing: 7) {
            header
            if all.isEmpty {
                Text("Nothing open.").font(serif(14).italic()).foregroundColor(inkSoft)
                Spacer(minLength: 0)
            } else {
                GeometryReader { geo in
                    let roomy = plan(all, .roomy, height: geo.size.height)
                    let compact = plan(all, .compact, height: geo.size.height)
                    // The larger type only when every task still fits with
                    // its title in full; otherwise the week widget's type,
                    // which gives up wrapping before it gives up a task.
                    if roomy.allSatisfy({ $0.complete }) {
                        ViewThatFits(in: .vertical) {
                            columns(roomy, .roomy, cascade: false)
                            columns(compact, .compact, cascade: true)
                        }
                    } else {
                        columns(compact, .compact, cascade: true)
                    }
                }
            }
        }
        .padding(inset)
    }

    /// Lay the blocks out in one column or two and give every block its
    /// share of the rows that fit.
    private func plan(_ all: [TodoBlock], _ t: TodoType, height: CGFloat) -> [TodoColumn] {
        func fill(_ part: [TodoBlock]) -> TodoColumn {
            let heads = part.filter { $0.title != nil }.count
            let fixed = CGFloat(heads) * t.head + CGFloat(max(0, part.count - 1)) * t.gap
            var budget = max(0, Int((height - fixed) / t.line))
            // A run with no heading says "+3 more" on a line of its own.
            if let run = part.first, run.title == nil, run.count > min(run.rows.count, budget) {
                budget = max(0, budget - 1)
            }
            return TodoColumn(blocks: part,
                              take: CalStore.share(part.map { $0.rows.count }, budget: budget))
        }
        guard family != .systemSmall else { return [fill(all)] }

        if all.count == 1, let run = all.first {
            // One run: a single column while it fits, so the titles get the
            // whole width; two balanced ones when it does not.
            let fits = Int(height / t.line)
            let extra = run.count > run.rows.count ? 1 : 0
            if run.rows.count + extra <= fits || fits < 1 { return [fill(all)] }
            let hidden = run.count > min(run.rows.count, 2 * fits) ? 1 : 0
            let shown = min(run.rows.count, 2 * fits - hidden)
            let left = min(fits, (shown + hidden + 1) / 2)
            return [
                fill([TodoBlock(title: nil, tint: run.tint, count: left,
                                rows: Array(run.rows.prefix(left)))]),
                fill([TodoBlock(title: nil, tint: run.tint, count: run.count - left,
                                rows: Array(run.rows.dropFirst(left)))]),
            ]
        }

        let k = CalStore.split(all.map { $0.rows.count }, head: t.head, line: t.line, gap: t.gap)
        return [fill(Array(all.prefix(k))), fill(Array(all.dropFirst(k)))]
    }

    private func columns(_ cols: [TodoColumn], _ t: TodoType, cascade: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(cols.enumerated()), id: \.offset) { _, col in
                column(col, t, cascade: cascade)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private func column(_ col: TodoColumn, _ t: TodoType, cascade: Bool) -> some View {
        let rows = col.take.reduce(0, +)
        if cascade {
            // Whatever height the rows leave over goes to long titles: the
            // first arrangement that fits wins — every title on up to three
            // lines, then as many as it can (soonest first) on two, down to
            // the plain one line each.
            let tries: [(rows: Int, lines: Int)] =
                [(rows, 3)] + (0...rows).reversed().map { ($0, 2) }
            ViewThatFits(in: .vertical) {
                ForEach(Array(tries.enumerated()), id: \.offset) { _, a in
                    stack(col, t, wrap: a.rows, lines: a.lines)
                }
            }
        } else {
            stack(col, t, wrap: rows, lines: 3)
        }
    }

    /// The first `wrap` rows of the column may run to `lines` lines.
    private func stack(_ col: TodoColumn, _ t: TodoType, wrap: Int, lines: Int) -> some View {
        var starts: [Int] = []
        var sum = 0
        for n in col.take { starts.append(sum); sum += n }
        return VStack(alignment: .leading, spacing: t.gap) {
            ForEach(Array(col.blocks.enumerated()), id: \.offset) { i, b in
                block(b, take: col.take[i], t) { starts[i] + $0 < wrap ? lines : 1 }
            }
        }
    }

    private func block(_ b: TodoBlock, take: Int, _ t: TodoType,
                       lines: @escaping (Int) -> Int) -> some View {
        let more = b.count - take
        return VStack(alignment: .leading, spacing: 0) {
            if let title = b.title {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(title)
                        .font(.system(size: t.title, weight: .bold))
                        .foregroundColor(b.tint)
                        .lineLimit(1)
                    Text("\(b.count)")
                        .font(.system(size: t.title - 1.5)).foregroundColor(inkSoft)
                    Spacer(minLength: 2)
                    if more > 0 {
                        Text("+\(more) more")
                            .font(.system(size: 9)).foregroundColor(inkSoft).fixedSize()
                    }
                }
                .frame(height: t.head)
            }
            ForEach(Array(b.rows.prefix(take).enumerated()), id: \.offset) { i, row in
                let n = lines(i)
                TaskLine(item: row.item, tint: row.tint, now: now, titleSize: t.title, lines: n)
                    .frame(minHeight: t.line)
                    .frame(height: n == 1 ? t.line : nil)
            }
            if b.title == nil && more > 0 {
                Text("+\(more) more")
                    .font(.system(size: 9)).foregroundColor(inkSoft)
                    .padding(.leading, 6.5)
                    .frame(height: t.line)
            }
        }
    }
}

// ── the widgets ───────────────────────────────────────────────────────────
//
// Three kinds rather than a configurable one: the picker in the widget
// editor is the same gesture, and this needs no AppIntents and no dynamic
// entity query — less to go wrong on a free signing team.

struct TodoAllWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodoAllWidget", provider: TodoProvider(listId: nil)) {
            TodoWidgetView(entry: $0)
        }
        .configurationDisplayName("Do. — every list")
        .description("Your open tasks across every list.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryInline, .accessoryCircular, .accessoryRectangular
        ])
    }
}

struct TodoPersonalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodoPersonalWidget",
                            provider: TodoProvider(listId: "personal")) {
            TodoWidgetView(entry: $0)
        }
        .configurationDisplayName("Do. — Personal")
        .description("The Personal list only.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryInline, .accessoryCircular, .accessoryRectangular
        ])
    }
}

struct TodoBusinessWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodoBusinessWidget",
                            provider: TodoProvider(listId: "business")) {
            TodoWidgetView(entry: $0)
        }
        .configurationDisplayName("Do. — Business")
        .description("The Business list only.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryInline, .accessoryCircular, .accessoryRectangular
        ])
    }
}

@main
struct TodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Calendar first: it is the one most people add, and the gallery
        // shows them in this order.
        CalTodayWidget()
        CalWeekWidget()
        CalAgendaWidget()
        TodoAllWidget()
        TodoPersonalWidget()
        TodoBusinessWidget()
    }
}
