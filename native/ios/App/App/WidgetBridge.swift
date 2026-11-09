import Foundation
import Capacitor
import WidgetKit

/// Lets the web layer tell WidgetKit that the shared payload changed.
///
/// Without this the widget would only refresh on its own timeline, which iOS
/// throttles to roughly every 5–15 minutes — the exact complaint about the
/// Scriptable widget this replaces. `WidgetCenter.reloadAllTimelines()` is not
/// reachable from JavaScript, so it needs these few lines of bridge.
///
/// The plugin is optional by design: index.html null-checks it, so if
/// Capacitor ever fails to register it the app still works and the widget
/// simply falls back to its own refresh schedule.
@objc(WidgetBridgePlugin)
public class WidgetBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "WidgetBridgePlugin"
    public let jsName = "WidgetBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "reload", returnType: CAPPluginReturnPromise)
    ]

    @objc func reload(_ call: CAPPluginCall) {
        WidgetCenter.shared.reloadAllTimelines()
        call.resolve()
    }
}
