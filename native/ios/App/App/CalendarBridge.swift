import Foundation
import Capacitor
import EventKit

/// Reads the phone's real calendars, so Do. can show the day you actually
/// have rather than only the part of it that it wrote itself.
///
/// This is the answer to "can it show my other calendar accounts". On the
/// web each provider is its own integration — a Microsoft app registration,
/// a Google Cloud project, and nothing at all for iCloud, which has no
/// public API. On the phone they are already there: whatever accounts are
/// set up in iOS Settings, Outlook and Google and iCloud alike, EventKit
/// hands over in one list behind one permission prompt.
///
/// Reading is everything except one calendar. The store can create and
/// delete events as easily as it can read them, and a to-do app that can
/// silently remove a meeting is a bad idea however carefully it is written.
/// So writing exists in exactly one place: a calendar Do. makes for itself,
/// called "Do.", holding the person's dated tasks, and only once they have
/// switched it on. Every write below checks it is touching that calendar
/// and no other, and only events Do. itself tagged. See "Writing".
@objc(CalendarBridgePlugin)
public class CalendarBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CalendarBridgePlugin"
    public let jsName = "CalendarBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "access", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "events", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "calendars", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "writeTasks", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "removeCalendar", returnType: CAPPluginReturnPromise)
    ]

    /// One store for the life of the app. Making a new EKEventStore per call
    /// drops the permission grant and re-prompts, and is slow besides.
    private let store = EKEventStore()

    // MARK: - Permission

    /// Resolves with what we are allowed to do, never rejects. A refusal is
    /// an answer — the calendar simply shows the tasks, as it did before any
    /// of this existed — and a rejected promise would turn that into an
    /// error the web layer has to catch and interpret.
    @objc func access(_ call: CAPPluginCall) {
        let report: (Bool) -> Void = { granted in
            call.resolve(["granted": granted])
        }
        if #available(iOS 17.0, *) {
            // Full access, not "write only": write-only is for apps that add
            // events without reading them, which is the opposite of this.
            store.requestFullAccessToEvents { granted, _ in
                DispatchQueue.main.async { report(granted) }
            }
        } else {
            store.requestAccess(to: .event) { granted, _ in
                DispatchQueue.main.async { report(granted) }
            }
        }
    }

    private var authorised: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    // MARK: - Reading

    /// Every calendar the phone knows about, so the web layer can offer the
    /// same tick-list every calendar app offers.
    @objc func calendars(_ call: CAPPluginCall) {
        guard authorised else { call.resolve(["granted": false, "calendars": []]); return }
        // Do.'s own calendar is not offered: its events are the tasks
        // already on screen, and showing them again would double every one.
        let list = store.calendars(for: .event).filter { !isOwn($0) }.map { cal -> [String: Any] in
            return [
                "id": cal.calendarIdentifier,
                "title": cal.title,
                // The account it came from: "Mylo", "iCloud", "Gmail". This
                // is the word a person recognises, not the calendar's name.
                "account": cal.source?.title ?? "",
                "colour": Self.hex(cal.cgColor),
                "readOnly": !cal.allowsContentModifications
            ]
        }
        call.resolve(["granted": true, "calendars": list])
    }

    /// Events between two instants, given and returned as milliseconds since
    /// the epoch so the web layer never has to parse a date string — which
    /// is where time zones go wrong.
    @objc func events(_ call: CAPPluginCall) {
        guard authorised else { call.resolve(["granted": false, "events": []]); return }
        guard let fromMs = call.getDouble("from"), let toMs = call.getDouble("to") else {
            call.reject("from and to are required, in milliseconds")
            return
        }
        let from = Date(timeIntervalSince1970: fromMs / 1000)
        let to = Date(timeIntervalSince1970: toMs / 1000)

        // Only the calendars the person has not switched off. Hidden
        // calendars are hidden everywhere else on the phone; showing them
        // here would be Do. disagreeing with iOS about what you asked for.
        let visible = store.calendars(for: .event).filter { !isOwn($0) }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: visible)

        let found = store.events(matching: predicate).map { ev -> [String: Any] in
            return [
                // eventIdentifier is stable for a single event but shared by
                // every occurrence of a repeating one, so the start time has
                // to go into any key the web layer builds from this.
                "id": ev.eventIdentifier ?? UUID().uuidString,
                "title": ev.title ?? "(no title)",
                "start": (ev.startDate?.timeIntervalSince1970 ?? 0) * 1000,
                "end": (ev.endDate?.timeIntervalSince1970 ?? 0) * 1000,
                "allDay": ev.isAllDay,
                "where": ev.location ?? "",
                "calendar": ev.calendar?.title ?? "",
                "account": ev.calendar?.source?.title ?? "",
                "colour": Self.hex(ev.calendar?.cgColor),
                // Everything a person opens an event to find out. Notes can
                // be long and carry the dial-in details, so they are not
                // trimmed here — the view decides how much to show.
                "notes": ev.notes ?? "",
                "url": ev.url?.absoluteString ?? "",
                "organiser": ev.organizer?.name ?? "",
                "attendees": (ev.attendees ?? []).compactMap { who -> [String: Any]? in
                    let name = who.name ?? who.url.absoluteString
                        .replacingOccurrences(of: "mailto:", with: "")
                    if name.isEmpty { return nil }
                    return [
                        "name": name,
                        "status": Self.status(who.participantStatus),
                        "me": who.isCurrentUser
                    ]
                },
                // Whether iOS will let this be changed at all: a meeting
                // somebody else organises in a read-only subscribed
                // calendar cannot be, and offering to edit it would be a
                // promise the app cannot keep.
                "editable": ev.calendar?.allowsContentModifications ?? false,
                "mine": ev.organizer?.isCurrentUser ?? false,
                // Seconds since Apple's 2001 reference date: what the
                // calshow: URL scheme wants in order to open the Calendar
                // app on this event's day.
                "appleTime": (ev.startDate ?? Date()).timeIntervalSinceReferenceDate,
                // A declined invitation is not your day. It is still
                // reported, so the web layer can decide, rather than being
                // dropped here where that decision would be invisible.
                "declined": ev.status == .canceled
            ]
        }
        call.resolve(["granted": true, "events": found])
    }

    // MARK: - Writing (Do.'s own calendar, nothing else)

    private static let ownKey = "do.calendar.own.id"
    private static let ownTitle = "Do."
    /// Every event Do. writes carries this in its URL, with the task's id.
    /// An event without it was put there by someone else and is left alone,
    /// even inside Do.'s own calendar.
    private static let tag = "x-do-task:"
    /// How far back and ahead the calendar is kept in step with the tasks.
    /// EventKit searches at most four years at a time; tasks outside this
    /// window are simply not written, rather than written again on every
    /// pass because the search could not see them.
    private static let back: TimeInterval = 400 * 86_400
    private static let ahead: TimeInterval = 1_000 * 86_400
    /// A task is a moment, not a meeting: a short entry, marked free, so
    /// it never makes the person look busy to anyone checking their time.
    private static let length: TimeInterval = 15 * 60

    private var ownId: String? {
        get { UserDefaults.standard.string(forKey: Self.ownKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.ownKey) }
    }

    private func isOwn(_ cal: EKCalendar) -> Bool {
        guard let id = ownId else { return false }
        return cal.calendarIdentifier == id
    }

    /// Where Do.'s calendar lives: iCloud when the phone has it, so the
    /// tasks reach the Mac and the iPad; otherwise "On My iPhone". Never a
    /// work account: an Exchange or Google calendar belongs to somebody's
    /// employer or another service, and Do. has no business adding to it.
    private func home() -> EKSource? {
        let sources = store.sources
        if let icloud = sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }) {
            return icloud
        }
        return sources.first(where: { $0.sourceType == .local })
    }

    /// The one calendar Do. may change. Found by the identifier it was given
    /// when it was made; failing that (a reinstall, or a second device on
    /// the same iCloud) by its name in Do.'s home account; failing that,
    /// made, when making is allowed.
    private func ownCalendar(create: Bool) throws -> EKCalendar? {
        if let id = ownId, let cal = store.calendar(withIdentifier: id), cal.allowsContentModifications {
            return cal
        }
        guard let source = home() else { return nil }
        if let found = store.calendars(for: .event).first(where: {
            $0.title == Self.ownTitle && $0.allowsContentModifications &&
            $0.source?.sourceIdentifier == source.sourceIdentifier
        }) {
            ownId = found.calendarIdentifier
            return found
        }
        guard create else { return nil }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = Self.ownTitle
        cal.source = source
        cal.cgColor = CGColor(red: 0.784, green: 0.333, blue: 0.239, alpha: 1)   // Do.'s red
        try store.saveCalendar(cal, commit: true)
        ownId = cal.calendarIdentifier
        return cal
    }

    private static func taskId(of ev: EKEvent) -> String? {
        guard let s = ev.url?.absoluteString, s.hasPrefix(tag) else { return nil }
        return String(s.dropFirst(tag.count)).removingPercentEncoding
    }

    private static func url(for id: String) -> URL? {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return URL(string: tag + safe)
    }

    private struct Wanted { let title: String; let start: Date; let notes: String }

    /// Makes the event say what the task says. Reports whether anything
    /// changed, so an unchanged task is not saved (and re-synced to every
    /// device on the account) for nothing.
    private static func apply(_ w: Wanted, to ev: EKEvent, alarm: Bool) -> Bool {
        var changed = false
        if ev.title != w.title { ev.title = w.title; changed = true }
        if ev.startDate != w.start { ev.startDate = w.start; changed = true }
        let end = w.start.addingTimeInterval(length)
        if ev.endDate != end { ev.endDate = end; changed = true }
        if ev.isAllDay { ev.isAllDay = false; changed = true }
        if (ev.notes ?? "") != w.notes { ev.notes = w.notes; changed = true }
        if ev.availability != .free { ev.availability = .free; changed = true }
        // One alert, never two: the phone's own reminder rings unless the
        // person chose Apple Calendar's instead, and then only this does.
        let hasAlarm = !(ev.alarms ?? []).isEmpty
        if alarm && !hasAlarm { ev.alarms = [EKAlarm(relativeOffset: 0)]; changed = true }
        if !alarm && hasAlarm { ev.alarms = nil; changed = true }
        return changed
    }

    /// Brings Do.'s calendar into line with the dated tasks the web layer
    /// sends: { items: [{ id, title, due (ms), notes }], alarm: Bool }.
    /// New tasks are added, changed ones moved, finished or deleted ones
    /// removed, and a task written twice (two devices on one iCloud, both
    /// quick) is left with one entry.
    @objc func writeTasks(_ call: CAPPluginCall) {
        guard authorised else { call.resolve(["ok": false, "reason": "permission"]); return }
        let alarm = call.getBool("alarm") ?? false
        let now = Date()
        let from = now.addingTimeInterval(-Self.back), to = now.addingTimeInterval(Self.ahead)

        var wanted: [String: Wanted] = [:]
        for item in call.getArray("items", JSObject.self) ?? [] {
            guard let id = item["id"] as? String, !id.isEmpty,
                  let title = item["title"] as? String,
                  let due = (item["due"] as? Double) ?? (item["due"] as? Int).map(Double.init) else { continue }
            let start = Date(timeIntervalSince1970: due / 1000)
            guard start >= from, start < to else { continue }
            wanted[id] = Wanted(title: title, start: start, notes: (item["notes"] as? String) ?? "")
        }

        do {
            guard let cal = try ownCalendar(create: true) else {
                call.resolve(["ok": false, "reason": "nowhere"])
                return
            }
            let mine = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: [cal]))
            var seen = Set<String>()
            var added = 0, moved = 0, removed = 0
            for ev in mine {
                // Belt and braces: the search was for this calendar alone.
                guard ev.calendar?.calendarIdentifier == cal.calendarIdentifier else { continue }
                guard let id = Self.taskId(of: ev) else { continue }     // not ours: leave it
                if let w = wanted[id], !seen.contains(id) {
                    seen.insert(id)
                    if Self.apply(w, to: ev, alarm: alarm) {
                        try store.save(ev, span: .thisEvent, commit: false)
                        moved += 1
                    }
                } else {
                    try store.remove(ev, span: .thisEvent, commit: false)
                    removed += 1
                }
            }
            for (id, w) in wanted where !seen.contains(id) {
                let ev = EKEvent(eventStore: store)
                ev.calendar = cal
                ev.url = Self.url(for: id)
                _ = Self.apply(w, to: ev, alarm: alarm)
                try store.save(ev, span: .thisEvent, commit: false)
                added += 1
            }
            try store.commit()
            call.resolve([
                "ok": true, "count": wanted.count,
                "added": added, "changed": moved, "removed": removed,
                "calendar": cal.title,
                // iOS calls the phone's own account "Default"; people know
                // it by the name the Calendar app shows.
                "account": cal.source?.sourceType == .local ? "On My iPhone" : (cal.source?.title ?? "")
            ])
        } catch {
            store.reset()
            call.resolve(["ok": false, "reason": error.localizedDescription])
        }
    }

    /// Switching the feature off deletes Do.'s calendar, and only that: it
    /// is found by the identifier Do. was given when it made it, and a
    /// calendar the person has since renamed is left where it is.
    @objc func removeCalendar(_ call: CAPPluginCall) {
        guard authorised else { call.resolve(["ok": false, "reason": "permission"]); return }
        guard let id = ownId, let cal = store.calendar(withIdentifier: id) else {
            ownId = nil
            call.resolve(["ok": true, "removed": false])
            return
        }
        guard cal.title == Self.ownTitle else {
            ownId = nil
            call.resolve(["ok": true, "removed": false, "reason": "renamed"])
            return
        }
        do {
            try store.removeCalendar(cal, commit: true)
            ownId = nil
            call.resolve(["ok": true, "removed": true])
        } catch {
            call.resolve(["ok": false, "reason": error.localizedDescription])
        }
    }

    // MARK: - Helpers

    /// The words a person recognises, not the enum.
    private static func status(_ s: EKParticipantStatus) -> String {
        switch s {
        case .accepted:  return "accepted"
        case .declined:  return "declined"
        case .tentative: return "maybe"
        case .pending:   return "no reply"
        default:         return ""
        }
    }

    /// EventKit hands out a CGColor; the web layer wants "#rrggbb".
    private static func hex(_ cg: CGColor?) -> String {
        guard let cg = cg, let comps = cg.components, comps.count >= 3 else { return "#735a99" }
        let r = Int((comps[0] * 255).rounded())
        let g = Int((comps[1] * 255).rounded())
        let b = Int((comps[2] * 255).rounded())
        return String(format: "#%02x%02x%02x", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }
}
