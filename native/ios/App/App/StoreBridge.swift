import Foundation
import Capacitor
import StoreKit
import SwiftUI
import Security

// MARK: - What is for sale

/// The two things Do. sells. The identifiers are the contract with App Store
/// Connect: the products created there must carry exactly these.
///
/// The monthly plan is deliberately the worse deal. It is on the screen so
/// that the lifetime price beside it reads as the obvious one: for good, for
/// less than four months of renting.
enum Plan {
    static let monthly = "com.ahmedmohsen.todolist.monthly"     // auto-renewing: $2.99, EGP 149.99 in Egypt
    static let lifetime = "com.ahmedmohsen.todolist.lifetime"   // non-consumable: $9.99, EGP 499 in Egypt
    static let all: Set<String> = [monthly, lifetime]
}

/// What the two plans are meant to cost, for the one moment the App Store
/// cannot say: before the products exist there. These figures are drawn only
/// on the preview below, which cannot be tapped and disappears the day
/// `Store.enforced` is switched on. A price anybody can pay always comes from
/// StoreKit, in the buyer's own currency.
enum Intended {
    static var egypt: Bool {
        if #available(iOS 16, *) { return Locale.current.region?.identifier == "EG" }
        return (Locale.current as NSLocale).countryCode == "EG"
    }
    static var monthly: (text: String, value: Double) { egypt ? ("EGP 149.99", 149.99) : ("$2.99", 2.99) }
    static var lifetime: (text: String, value: Double) { egypt ? ("EGP 499", 499) : ("$9.99", 9.99) }

    /// "Less than 4 months of the monthly plan", worked out from the two
    /// prices on the screen — so it is true in every currency, or it is not
    /// said at all.
    static func worth(lifetime: Double, monthly: Double) -> String? {
        guard monthly > 0, lifetime > monthly else { return nil }
        let ratio = lifetime / monthly
        let whole = ratio.rounded(.up)
        return whole == ratio ? "The price of \(Int(whole)) months of the monthly plan"
                              : "Less than \(Int(whole)) months of the monthly plan"
    }
}

// MARK: - The fourteen free days

/// The fourteen days start the first time the app runs and are counted from
/// a date in the Keychain, which survives deleting the app; a date in
/// localStorage would hand out a fresh trial to anyone who reinstalled.
///
/// A second value keeps the latest moment the app has ever seen. The trial
/// is measured from whichever is later, that or the clock, so winding the
/// phone's date back does not wind the trial back with it.
enum TrialClock {
    static let days = 14
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

    /// The one switch. While this is false nothing is ever locked: the trial
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
            "trialDays": TrialClock.days,
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
                    point("Three columns, side by side, on the open iPhone Duo")
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
        case "expired": return "Your \(TrialClock.days) free days have ended."
        default:
            let d = status["trialDaysLeft"] as? Int ?? 0
            return d == 1 ? "One day left of your \(TrialClock.days) free days."
                          : "\(d) days left of your \(TrialClock.days) free days."
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
            if Store.enforced {
                notice("The plans could not be loaded.",
                       "Check the connection and open this screen again. Everything you have written is still here.")
            } else {
                // Before the products exist in App Store Connect: the two
                // plans as they will be, to look at and not to tap.
                VStack(alignment: .leading, spacing: 12) {
                    card(lifetime: true, price: Intended.lifetime.text,
                         worth: Intended.worth(lifetime: Intended.lifetime.value, monthly: Intended.monthly.value),
                         mine: false, busy: false, action: nil)
                    card(lifetime: false, price: Intended.monthly.text, worth: nil,
                         mine: false, busy: false, action: nil)
                    Text("These open with the App Store release. Until then nothing is locked and nothing can be bought.")
                        .font(.system(size: 13))
                        .foregroundColor(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .ready:
            VStack(spacing: 12) {
                ForEach(store.products, id: \.id) { product in
                    card(lifetime: product.id == Plan.lifetime,
                         price: product.displayPrice,
                         worth: product.id == Plan.lifetime ? worth : nil,
                         mine: store.owned.contains(product.id),
                         busy: store.busy == product.id) {
                        Task { await store.buy(product) }
                    }
                }
            }
        }
    }

    /// The lifetime price measured in months of the monthly one, from the
    /// prices StoreKit gave for this storefront.
    private var worth: String? {
        guard let once = store.products.first(where: { $0.id == Plan.lifetime }),
              let month = store.products.first(where: { $0.id == Plan.monthly }) else { return nil }
        return Intended.worth(lifetime: NSDecimalNumber(decimal: once.price).doubleValue,
                              monthly: NSDecimalNumber(decimal: month.price).doubleValue)
    }

    private func notice(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundColor(Palette.ink)
            Text(body)
                .font(.system(size: 14))
                .foregroundColor(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.rule))
    }

    /// One plan. With an action it is a button that hands over to Apple's
    /// payment sheet; without one it is a picture of a plan and nothing more.
    @ViewBuilder
    private func card(lifetime: Bool, price: String, worth: String?, mine: Bool, busy: Bool,
                      action: (() -> Void)?) -> some View {
        let face = HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if worth != nil {
                    Text("BEST VALUE")
                        .font(.system(size: 10, weight: .heavy))
                        .kerning(0.6)
                        .foregroundColor(Palette.card)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Palette.red))
                        .padding(.bottom, 3)
                }
                Text(lifetime ? "Once, for good" : "Monthly")
                    .font(.system(size: 19, weight: .bold, design: .serif))
                Text(lifetime ? "Pay once. No renewals, ever."
                              : "Renews each month. Cancel any time.")
                    .font(.system(size: 13))
                    .opacity(0.8)
                if let worth {
                    Text(worth)
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if busy {
                ProgressView().tint(lifetime ? Palette.card : Palette.ink)
            } else if mine {
                Text("Yours").font(.system(size: 15, weight: .bold))
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(price)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize()
                    Text(lifetime ? "once" : "a month").font(.system(size: 11)).opacity(0.75)
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
        if let action {
            Button(action: action) { face }
                .disabled(store.busy != nil || mine)
        } else {
            face
        }
    }
}
