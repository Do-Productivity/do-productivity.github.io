import Foundation
import Capacitor
import StoreKit
import SwiftUI
import Security

// MARK: - What is for sale

/// The two things Do. sells. The identifiers are the contract with App Store
/// Connect: the products created there must carry exactly these.
enum Plan {
    static let monthly = "com.ahmedmohsen.todolist.monthly"     // auto-renewing, $0.99
    static let lifetime = "com.ahmedmohsen.todolist.lifetime"   // non-consumable, $9.99
    static let all: Set<String> = [monthly, lifetime]
}

// MARK: - The free month

/// The thirty days start the first time the app runs and are counted from a
/// date in the Keychain, which survives deleting the app; a date in
/// localStorage would hand out a fresh month to anyone who reinstalled.
///
/// A second value keeps the latest moment the app has ever seen. The trial
/// is measured from whichever is later, that or the clock, so winding the
/// phone's date back does not wind the month back with it.
enum TrialClock {
    static let days = 30
    private static let service = "com.ahmedmohsen.todolist.entitlement"
    private static let startedKey = "trial_started_v1"
    private static let seenKey = "latest_seen_v1"

    private static func read(_ account: String) -> Double? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let s = String(data: data, encoding: .utf8) else { return nil }
        return Double(s)
    }

    private static func write(_ account: String, _ value: Double) {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(match as CFDictionary)
        var add = match
        add[kSecValueData as String] = String(value).data(using: .utf8)!
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false
        SecItemAdd(add as CFDictionary, nil)
    }

    /// The moment to measure from: never earlier than anything already seen.
    static func now() -> Date {
        let clock = Date().timeIntervalSince1970
        let seen = read(seenKey) ?? 0
        // write at most once a minute; this is called on every status check
        if clock > seen + 60 { write(seenKey, clock) }
        return Date(timeIntervalSince1970: max(clock, seen))
    }

    static func started() -> Date {
        if let s = read(startedKey) { return Date(timeIntervalSince1970: s) }
        let t = Date().timeIntervalSince1970
        write(startedKey, t)
        return Date(timeIntervalSince1970: t)
    }

    static func ends() -> Date {
        started().addingTimeInterval(Double(days) * 86_400)
    }
}

// MARK: - The store

/// Who has paid, decided here and nowhere else.
///
/// The web layer is told the answer and may draw it; it is never asked. A
/// boolean in JavaScript is a boolean anybody with a web inspector can set,
/// so nothing in `index.html` is ever the source of this.
///
/// "Paid" means StoreKit 2 handed over a transaction it has verified against
/// Apple's signature, for one of our two products, that has not been refunded
/// or revoked and — for the subscription — has not lapsed.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    /// The one switch. While this is false nothing is ever locked: the month
    /// is counted and the plans can be shown, but running out changes
    /// nothing. It becomes true in the release that ships with the products
    /// live in App Store Connect, and not before — an enforced paywall with
    /// nothing purchasable behind it is a locked door with no key.
    static let enforced = false

    enum Load { case loading, ready, unavailable }

    @Published private(set) var products: [Product] = []
    @Published private(set) var owned: Set<String> = []
    @Published private(set) var load: Load = .loading
    @Published var busy: String?
    @Published var note: String?

    var changed: (() -> Void)?
    private var updates: Task<Void, Never>?

    func start() {
        guard updates == nil else { return }
        // Purchases that complete outside the app — approved by a parent,
        // bought on another device, renewed, refunded — arrive here.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task {
            await refresh()
            await loadProducts()
        }
    }

    func refresh() async {
        var mine = Set<String>()
        for await result in Transaction.currentEntitlements {
            // .unverified is dropped on the floor: it means the signature did
            // not check out, which is exactly the case this exists to refuse.
            guard case .verified(let t) = result else { continue }
            guard Plan.all.contains(t.productID), t.revocationDate == nil else { continue }
            if let end = t.expirationDate, end < Date() { continue }
            mine.insert(t.productID)
        }
        let was = owned
        owned = mine
        if was != mine { changed?() }
    }

    func loadProducts() async {
        load = .loading
        do {
            let found = try await Product.products(for: Plan.all)
            // lifetime first: it is the one most people should take
            products = found.sorted { a, _ in a.id == Plan.lifetime }
            load = found.isEmpty ? .unavailable : .ready
        } catch {
            products = []
            load = .unavailable
        }
        changed?()
    }

    func buy(_ product: Product) async {
        guard busy == nil else { return }
        busy = product.id
        note = nil
        defer { busy = nil }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let t) = result {
                    await t.finish()
                    await refresh()
                } else {
                    note = "Apple could not confirm that purchase, so nothing was unlocked and nothing was charged to keep."
                }
            case .pending:
                note = "Waiting for approval. Do. will unlock by itself when it comes through."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            note = "The purchase did not go through. Nothing was charged."
        }
    }

    func restore() async {
        guard busy == nil else { return }
        busy = "restore"
        note = nil
        defer { busy = nil }
        do {
            try await AppStore.sync()
            await refresh()
            if owned.isEmpty { note = "No earlier purchase was found for this Apple ID." }
        } catch {
            // the person cancelled the sign-in sheet; nothing to say
        }
    }

    // What the web layer is told.
    func status() -> [String: Any] {
        let now = TrialClock.now()
        let ends = TrialClock.ends()
        let left = max(0, Int(ceil(ends.timeIntervalSince(now) / 86_400)))
        let state: String
        if owned.contains(Plan.lifetime) { state = "lifetime" }
        else if owned.contains(Plan.monthly) { state = "subscribed" }
        else if now < ends { state = "trial" }
        else { state = "expired" }
        return [
            "state": state,
            "entitled": state != "expired" || !Store.enforced,
            "enforced": Store.enforced,
            "trialDaysLeft": left,
            "trialEndsAt": ends.timeIntervalSince1970 * 1000,
            "storeReady": load == .ready
        ]
    }
}

// MARK: - The bridge

@objc(StoreBridgePlugin)
public class StoreBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "StoreBridgePlugin"
    public let jsName = "StoreBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "status", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "showPlans", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "restore", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "manage", returnType: CAPPluginReturnPromise)
    ]

    override public func load() {
        Task { @MainActor [weak self] in
            Store.shared.changed = { [weak self] in
                self?.notifyListeners("entitlement", data: Store.shared.status())
            }
            Store.shared.start()
        }
    }

    @objc func status(_ call: CAPPluginCall) {
        Task { @MainActor in
            await Store.shared.refresh()
            call.resolve(Store.shared.status())
        }
    }

    /// There is deliberately no `purchase(productId)` method. Buying happens
    /// on a native screen the person can see and Apple's own payment sheet;
    /// the web layer can open that screen and cannot do anything else.
    @objc func showPlans(_ call: CAPPluginCall) {
        Task { @MainActor in
            guard let host = self.bridge?.viewController, host.presentedViewController == nil else {
                call.resolve(Store.shared.status())
                return
            }
            let sheet = UIHostingController(rootView: PlansView(store: Store.shared) { [weak host] in
                host?.dismiss(animated: true)
            })
            sheet.modalPresentationStyle = .pageSheet
            sheet.view.backgroundColor = UIColor(Palette.paper)
            host.present(sheet, animated: true)
            if Store.shared.load != .ready { await Store.shared.loadProducts() }
            call.resolve(Store.shared.status())
        }
    }

    @objc func restore(_ call: CAPPluginCall) {
        Task { @MainActor in
            await Store.shared.restore()
            call.resolve(Store.shared.status())
        }
    }

    /// Cancelling has to be as easy as subscribing. This opens Apple's own
    /// subscriptions page, where it is two taps.
    @objc func manage(_ call: CAPPluginCall) {
        Task { @MainActor in
            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                await UIApplication.shared.open(url)
            }
            call.resolve()
        }
    }
}

// MARK: - The screen

enum Palette {
    static let paper = Color(red: 0.969, green: 0.953, blue: 0.914)
    static let card = Color(red: 1.0, green: 0.992, blue: 0.969)
    static let ink = Color(red: 0.169, green: 0.149, blue: 0.125)
    static let inkSoft = Color(red: 0.42, green: 0.384, blue: 0.349)
    static let rule = Color(red: 0.851, green: 0.824, blue: 0.761)
    static let red = Color(red: 0.784, green: 0.333, blue: 0.239)
    static let green = Color(red: 0.29, green: 0.541, blue: 0.361)
}

/// The plans, drawn natively.
///
/// Every price on this screen comes from StoreKit, in the buyer's own
/// currency — none is typed into the app, so the screen cannot promise one
/// figure and charge another. There is no card field here or anywhere else
/// in Do.: tapping a plan hands over to Apple's payment sheet.
struct PlansView: View {
    @ObservedObject var store: Store
    let close: () -> Void

    private var status: [String: Any] { store.status() }
    private var state: String { status["state"] as? String ?? "trial" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: close) {
                        Text("Close")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Palette.ink)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(Capsule().fill(Palette.ink.opacity(0.08)))
                    }
                }
                .padding(.top, 18)

                (Text("Do").foregroundColor(Palette.ink) + Text(".").foregroundColor(Palette.red))
                    .font(.system(size: 54, weight: .bold, design: .serif))
                    .padding(.top, 6)

                Text(headline)
                    .font(.system(size: 21, weight: .regular, design: .serif))
                    .italic()
                    .foregroundColor(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 13) {
                    point("Every list, note and scheduled task")
                    point("Your calendar beside the things you owe it")
                    point("Sync across your devices, reminders that ring")
                    point("Widgets on the Home and Lock Screen")
                }
                .padding(.top, 26)

                plans.padding(.top, 28)

                if let note = store.note {
                    Text(note)
                        .font(.system(size: 14))
                        .foregroundColor(Palette.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }

                Button {
                    Task { await store.restore() }
                } label: {
                    HStack(spacing: 8) {
                        if store.busy == "restore" { ProgressView() }
                        Text("Restore purchases")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Palette.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .padding(.top, 10)
                .disabled(store.busy != nil)

                Text("Your lists are yours either way. If you never pay, everything you have written stays readable and can be exported. The monthly plan renews until you cancel, which you can do at any time in Settings › Apple ID › Subscriptions. Payment is taken by Apple; Do. never sees a card.")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
        .background(Palette.paper.ignoresSafeArea())
    }

    private var headline: String {
        switch state {
        case "lifetime": return "Yours for good. Thank you."
        case "subscribed": return "You are subscribed. Thank you."
        case "expired": return "Your free month has ended."
        default:
            let d = status["trialDaysLeft"] as? Int ?? 0
            return d == 1 ? "One day left of your free month."
                          : "\(d) days left of your free month."
        }
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle().fill(Palette.red).frame(width: 7, height: 7).offset(y: -2)
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var plans: some View {
        switch store.load {
        case .loading:
            HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 30)
        case .unavailable:
            VStack(alignment: .leading, spacing: 8) {
                Text("The plans are not on sale yet.")
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundColor(Palette.ink)
                Text("Nothing is locked in the meantime. When they open this is where they will be: one payment for good, or a small one each month that you can stop whenever you like.")
                    .font(.system(size: 14))
                    .foregroundColor(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.rule))
        case .ready:
            VStack(spacing: 12) {
                ForEach(store.products, id: \.id) { product in
                    planCard(product)
                }
            }
        }
    }

    private func planCard(_ product: Product) -> some View {
        let lifetime = product.id == Plan.lifetime
        let mine = store.owned.contains(product.id)
        return Button {
            Task { await store.buy(product) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lifetime ? "Once, for good" : "Monthly")
                        .font(.system(size: 19, weight: .bold, design: .serif))
                    Text(lifetime ? "Pay once. No renewals, ever."
                                  : "Renews each month. Cancel any time.")
                        .font(.system(size: 13))
                        .opacity(0.8)
                }
                Spacer(minLength: 8)
                if store.busy == product.id {
                    ProgressView().tint(lifetime ? Palette.card : Palette.ink)
                } else if mine {
                    Text("Yours").font(.system(size: 15, weight: .bold))
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(product.displayPrice)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                        if !lifetime {
                            Text("a month").font(.system(size: 11)).opacity(0.75)
                        }
                    }
                }
            }
            .foregroundColor(lifetime ? Palette.card : Palette.ink)
            .padding(.horizontal, 18).padding(.vertical, 17)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(lifetime ? Palette.ink : Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(lifetime ? Color.clear : Palette.rule)
            )
        }
        .disabled(store.busy != nil || mine)
    }
}
