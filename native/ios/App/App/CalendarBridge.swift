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
/// Read only for now, deliberately. The store can create and delete events
/// as easily as it can read them, and a to-do app that can silently remove
/// a meeting is a bad idea however carefully it is written. Writing is a
/// decision to be made on purpose, not a capability to leave lying around.
@objc(CalendarBridgePlugin)
public class CalendarBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CalendarBridgePlugin"
    public let jsName = "CalendarBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "access", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "events", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "calendars", returnType: CAPPluginReturnPromise)
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
        let list = store.calendars(for: .event).map { cal -> [String: Any] in
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
        let visible = store.calendars(for: .event).filter { $0.isSubscribed == false || $0.isSubscribed }
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
                // A declined invitation is not your day. It is still
                // reported, so the web layer can decide, rather than being
                // dropped here where that decision would be invisible.
                "declined": ev.status == .canceled
            ]
        }
        call.resolve(["granted": true, "events": found])
    }

    // MARK: - Helpers

    /// EventKit hands out a CGColor; the web layer wants "#rrggbb".
    private static func hex(_ cg: CGColor?) -> String {
        guard let cg = cg, let comps = cg.components, comps.count >= 3 else { return "#735a99" }
        let r = Int((comps[0] * 255).rounded())
        let g = Int((comps[1] * 255).rounded())
        let b = Int((comps[2] * 255).rounded())
        return String(format: "#%02x%02x%02x", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }
}
