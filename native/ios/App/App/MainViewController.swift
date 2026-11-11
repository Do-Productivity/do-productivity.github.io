import UIKit
import WebKit
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
        bridge?.registerPluginInstance(SecureStorePlugin())
        bridge?.registerPluginInstance(StoreBridgePlugin())
    }

    // MARK: The folded iPhone Duo's status pill

    /// Folded, the Duo draws its clock, signal and battery in a pill over the
    /// top right-hand corner of the app. The safe area does not describe it
    /// (it reports about 30pt where the pill reaches about 76pt), so the page
    /// could only guess. iOS 27.1 describes it as a reserved "occlusion"
    /// region; the page cannot ask for that, so it is handed two lengths as
    /// CSS variables: how far in from the right the pill reaches, and how far
    /// down.
    private var occlusionSent = ""

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reportOcclusion(force: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The page can finish loading after the first layout, and would then
        // never hear. Say it again a few times while it settles.
        for delay in [0.5, 1.5, 3.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.reportOcclusion(force: true)
            }
        }
    }

    private func reportOcclusion(force: Bool) {
        guard let web = webView else { return }
        var reach: CGFloat = 0, depth: CGFloat = 0
        if #available(iOS 27.1, *) {
            let bounds = web.bounds
            for region in web.reservedRegions(kind: .occlusion) where region.isActive {
                let frame = region.frame.intersection(bounds)
                if frame.isNull || frame.isEmpty { continue }
                // Only a pill in the top right-hand corner. A bar across the
                // whole top, or the island in the middle, is the safe area's job.
                guard frame.maxX >= bounds.maxX - 40,
                      frame.minY <= bounds.minY + 80,
                      frame.width < bounds.width * 0.6 else { continue }
                reach = max(reach, bounds.maxX - frame.minX)
                depth = max(depth, frame.maxY - bounds.minY)
            }
        }
        let js = "(function(){var s=document.documentElement.style;" +
            "s.setProperty('--occl-w','\(Int(reach.rounded(.up)))px');" +
            "s.setProperty('--occl-b','\(Int(depth.rounded(.up)))px');" +
            "window.dispatchEvent(new Event('occlusion'));})()"
        if !force && js == occlusionSent { return }
        occlusionSent = js
        web.evaluateJavaScript(js, completionHandler: nil)
    }
}
