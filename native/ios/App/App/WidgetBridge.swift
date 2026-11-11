import Foundation
import Capacitor
import WidgetKit

/// The one road from the web layer to the widgets.
///
/// `set` puts the payload where the widget extension can read it — the
/// App Group's own UserDefaults — and `reload` tells WidgetKit to redraw.
///
/// `set` exists because the Capacitor Preferences plugin cannot do this.
/// Its `group` option reads like an App Group but is only a prefix on the
/// key: `configure({ group: "group.x" })` followed by `set("widgetData")`
/// writes "group.x.widgetData" into the app's *own* defaults, which no
/// extension can see. The first version of this app wrote the widget
/// payload that way, so the calendar widgets were handed nothing at all
/// and said "Nothing left today" every day. (The list widgets hid it: they
/// fall back to the sync feed.)
///
/// Without `reload` the widget would only refresh on its own timeline, which
/// iOS throttles to roughly every 5–15 minutes.
///
/// The plugin is optional by design: index.html null-checks it, so if
/// Capacitor ever fails to register it the app still works and the widget
/// simply falls back to its own refresh schedule.
@objc(WidgetBridgePlugin)
public class WidgetBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    static let group = "group.com.ahmedmohsen.todolist.shared"

    public let identifier = "WidgetBridgePlugin"
    public let jsName = "WidgetBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "set", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "reload", returnType: CAPPluginReturnPromise)
    ]

    /// Writes the payload into the shared group and redraws the widgets.
    /// Rejects rather than pretending when the group is not there: a write
    /// that lands nowhere is exactly the fault this method replaces.
    @objc func set(_ call: CAPPluginCall) {
        guard let value = call.getString("value") else {
            call.reject("no value")
            return
        }
        let group = WidgetBridgePlugin.group
        guard FileManager.default.containerURL(
                  forSecurityApplicationGroupIdentifier: group) != nil,
              let defaults = UserDefaults(suiteName: group) else {
            call.reject("the shared App Group is not available to this build")
            return
        }
        defaults.set(value, forKey: "widgetData")
        // An older key the widget also reads; left behind it would win.
        defaults.removeObject(forKey: "CapacitorStorage.widgetData")
        WidgetCenter.shared.reloadAllTimelines()
        call.resolve(["shared": true])
    }

    @objc func reload(_ call: CAPPluginCall) {
        WidgetCenter.shared.reloadAllTimelines()
        call.resolve()
    }
}
