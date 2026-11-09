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
        let raw = defaults.string(forKey: "CapacitorStorage.widgetData")
            ?? defaults.string(forKey: "widgetData")
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
                items: sorted.prefix(8).map { TodoItem(text: $0.text ?? "", due: $0.due) }
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

private extension Color {
    static let paper = Color(red: 0.969, green: 0.953, blue: 0.914)   // #f7f3e9
    static let ink   = Color(red: 0.169, green: 0.149, blue: 0.125)   // #2b2620
    static let soft  = Color(red: 0.420, green: 0.384, blue: 0.349)   // #6b6259
    static let late  = Color(red: 0.761, green: 0.255, blue: 0.047)   // overdue
    static let good  = Color(red: 0.000, green: 0.659, blue: 0.420)   // #00A86B
}

private func dueLabel(_ ms: Double?) -> (String, Bool)? {
    guard let ms = ms else { return nil }
    let date = Date(timeIntervalSince1970: ms / 1000)
    let late = date < Date()
    let cal = Calendar.current
    let fmt = DateFormatter()
    if cal.isDateInToday(date) {
        fmt.dateFormat = "HH:mm"
        return (fmt.string(from: date), late)
    }
    if cal.isDateInTomorrow(date) {
        fmt.dateFormat = "HH:mm"
        return ("tmrw " + fmt.string(from: date), late)
    }
    fmt.dateFormat = "d MMM"
    return (fmt.string(from: date), late)
}

struct TaskRow: View {
    let item: TodoItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .strokeBorder(Color.soft.opacity(0.55), lineWidth: 1.2)
                .frame(width: 9, height: 9)
                .padding(.top, 2)
            Text(item.text)
                .font(.system(size: 12))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
            Spacer(minLength: 2)
            if let (label, late) = dueLabel(item.due) {
                Text(label)
                    .font(.system(size: 10, weight: late ? .semibold : .regular))
                    .foregroundStyle(late ? Color.late : Color.soft)
            }
        }
    }
}

struct TodoWidgetView: View {
    var entry: TodoEntry
    @Environment(\.widgetFamily) private var family

    private var lists: [TodoList] {
        let all = entry.payload?.lists ?? []
        guard let want = entry.listId else { return all }
        return all.filter { $0.id == want }
    }

    private var rowBudget: Int {
        switch family {
        case .systemSmall: return 4
        case .systemMedium: return 5
        default: return 11
        }
    }

    var body: some View {
        Group {
            if entry.payload == nil {
                VStack(spacing: 4) {
                    Text("No data yet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text("Open the app once")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.soft)
                }
            } else {
                content
            }
        }
        .containerBackground(for: .widget) { Color.paper }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text(entry.listId == nil ? "To Do" : (lists.first?.title ?? "To Do"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.ink)
            Spacer(minLength: 2)
            if let late = entry.payload?.overdue, late > 0 {
                Text("\(late) late")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.late)
            }
            if let today = entry.payload?.today, today > 0 {
                Text("\(today) today")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.good)
            }
        }
    }

    // One list: a plain run of tasks. Several: a titled block each, which is
    // the dashboard's own shape.
    private var content: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            if lists.count == 1, let only = lists.first {
                ForEach(only.items.prefix(rowBudget), id: \.self) { TaskRow(item: $0) }
                if only.count > rowBudget {
                    Text("+\(only.count - rowBudget) more")
                        .font(.system(size: 10)).foregroundStyle(Color.soft)
                }
                if only.items.isEmpty {
                    Text("Nothing open").font(.system(size: 11)).foregroundStyle(Color.soft)
                }
            } else {
                let share = max(1, rowBudget / max(1, min(lists.count, 3)))
                ForEach(lists.prefix(3), id: \.id) { list in
                    if !list.items.isEmpty {
                        Text(list.title.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Color.soft)
                            .padding(.top, 1)
                        ForEach(list.items.prefix(share), id: \.self) { TaskRow(item: $0) }
                    }
                }
            }
            Spacer(minLength: 0)
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
        .configurationDisplayName("To Do — everything")
        .description("Your open tasks across every list.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodoPersonalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodoPersonalWidget",
                            provider: TodoProvider(listId: "personal")) {
            TodoWidgetView(entry: $0)
        }
        .configurationDisplayName("To Do — Personal")
        .description("The Personal list only.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodoBusinessWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodoBusinessWidget",
                            provider: TodoProvider(listId: "business")) {
            TodoWidgetView(entry: $0)
        }
        .configurationDisplayName("To Do — Business")
        .description("The Business list only.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct TodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodoAllWidget()
        TodoPersonalWidget()
        TodoBusinessWidget()
    }
}
