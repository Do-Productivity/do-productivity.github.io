import UIKit
import Capacitor

/// The view controller the app actually runs in, and the only place our own
/// plugins get registered.
///
/// This exists because of a silent failure worth remembering. Capacitor used
/// to find plugins by walking the Objective-C runtime for anything inheriting
/// CAPPlugin, so a class in the app target simply appeared in
/// `window.Capacitor.Plugins`. That scan is gone — `CAPBridgedPlugin`, with
/// its `identifier`, `jsName` and `pluginMethods`, replaced it precisely so
/// that registration is explicit — and an unregistered plugin does not
/// complain. It is just missing.
///
/// Which is exactly how it went unnoticed: `index.html` null-checks every
/// plugin and carries on without it, so WidgetBridge was never registered,
/// never called, and the widget quietly fell back to refreshing on iOS's own
/// schedule. It looked like it worked. The diagnostic that found it was one
/// line printing `Object.keys(window.Capacitor.Plugins)`.
///
/// If a plugin ever seems absent from JavaScript again, print that list
/// first. The answer is usually here.
class MainViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(WidgetBridgePlugin())
        bridge?.registerPluginInstance(CalendarBridgePlugin())
    }
}
