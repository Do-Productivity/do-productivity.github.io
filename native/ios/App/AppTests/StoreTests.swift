import XCTest
import StoreKit
import StoreKitTest
@testable import App

/// Purchases and entitlements, against the products in Do.storekit.
///
/// These run in the simulator with StoreKit's test session, so nothing is
/// charged and no Apple Account is needed. They check what Store decides,
/// which is what the app shows and what it locks: the web layer only draws it.
@MainActor
final class StoreTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "Do")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        await Store.shared.refresh()
        await Store.shared.loadProducts()
    }

    override func tearDown() async throws {
        session.clearTransactions()
        await Store.shared.refresh()
    }

    private func product(_ id: String) throws -> Product {
        try XCTUnwrap(Store.shared.products.first { $0.id == id }, "\(id) was not loaded")
    }

    /// In this simulator the purchase sheet goes to Apple's real sandbox and
    /// asks for a sandbox Apple Account, which a test cannot type. Buying is
    /// therefore tested by hand, on the phone, with a sandbox tester. Set
    /// DO_LOCAL_PURCHASES=1 where StoreKit's local test session does answer.
    private func skipUnlessPurchasesAreLocal() throws {
        if ProcessInfo.processInfo.environment["DO_LOCAL_PURCHASES"] != "1" {
            throw XCTSkip("buying needs a sandbox Apple Account here; tested on the phone")
        }
    }

    private var state: String? { Store.shared.status()["state"] as? String }
    private var plan: String? { Store.shared.status()["plan"] as? String }

    func testThePaywallIsOn() {
        XCTAssertTrue(Store.enforced, "the release build must enforce the plans")
    }

    func testOnlyTheTwoPlansAreForSaleYearlyFirst() throws {
        let ids = Store.shared.products.map(\.id)
        XCTAssertEqual(Set(ids), [Plan.yearly, Plan.monthly])
        XCTAssertEqual(ids.first, Plan.yearly)
        XCTAssertFalse(ids.contains(Plan.lifetime), "the founding product is never offered for sale")
    }

    func testPricesAndPeriods() throws {
        let year = try product(Plan.yearly), month = try product(Plan.monthly)
        XCTAssertEqual(year.price, Decimal(string: "9.99"))
        XCTAssertEqual(month.price, Decimal(string: "2.99"))
        XCTAssertEqual(year.subscription?.subscriptionPeriod.unit, .year)
        XCTAssertEqual(month.subscription?.subscriptionPeriod.unit, .month)
        XCTAssertEqual(year.subscription?.subscriptionGroupID, month.subscription?.subscriptionGroupID,
                       "both plans in one group, so a person holds one at a time")
    }

    func testTheYearlyCardSaysWhatItSaves() {
        XCTAssertEqual(Intended.worth(yearly: 9.99, monthly: 2.99),
                       "A year for less than 4 months of the monthly plan")
        XCTAssertNil(Intended.worth(yearly: 40, monthly: 2.99), "never claimed when it is not cheaper")
    }

    func testBeforeBuyingNothingIsOwned() {
        XCTAssertTrue(Store.shared.owned.isEmpty)
        XCTAssertNotEqual(state, "subscribed")
        XCTAssertNotEqual(state, "lifetime")
    }

    func testBuyingTheYearlyPlan() async throws {
        try skipUnlessPurchasesAreLocal()
        await Store.shared.buy(try product(Plan.yearly))
        XCTAssertTrue(Store.shared.owned.contains(Plan.yearly))
        XCTAssertEqual(state, "subscribed")
        XCTAssertEqual(plan, "yearly")
        XCTAssertEqual(Store.shared.status()["entitled"] as? Bool, true)
        XCTAssertNil(Store.shared.note, "no error shown after a good purchase")
    }

    func testBuyingTheMonthlyPlan() async throws {
        try skipUnlessPurchasesAreLocal()
        await Store.shared.buy(try product(Plan.monthly))
        XCTAssertTrue(Store.shared.owned.contains(Plan.monthly))
        XCTAssertEqual(state, "subscribed")
        XCTAssertEqual(plan, "monthly")
    }

    func testAnExpiredSubscriptionStopsCounting() async throws {
        try skipUnlessPurchasesAreLocal()
        await Store.shared.buy(try product(Plan.monthly))
        XCTAssertTrue(Store.shared.owned.contains(Plan.monthly))
        try session.expireSubscription(productIdentifier: Plan.monthly)
        await Store.shared.refresh()
        XCTAssertFalse(Store.shared.owned.contains(Plan.monthly))
        XCTAssertNotEqual(state, "subscribed")
    }

    /// Restore asks Apple to sync (a sign-in sheet in real life, which a test
    /// cannot answer) and then reads the purchases again. The second half is
    /// what decides the result, so that is what is tested here.
    func testReadingPurchasesAgainFindsWhatWasBought() async throws {
        try skipUnlessPurchasesAreLocal()
        await Store.shared.buy(try product(Plan.yearly))
        await Store.shared.refresh()
        XCTAssertTrue(Store.shared.owned.contains(Plan.yearly))
        XCTAssertEqual(state, "subscribed")
    }

    /// A founding member's free Apple code arrives as an ordinary transaction
    /// for the lifetime product. In the test it is bought directly, which
    /// leaves the same transaction behind.
    private func foundingProduct() async throws -> Product {
        let found = try await Product.products(for: [Plan.lifetime])
        return try XCTUnwrap(found.first, "the founding product is in the store file")
    }

    func testAFoundingMemberCodeMakesItYoursForGood() async throws {
        try skipUnlessPurchasesAreLocal()
        await Store.shared.buy(try await foundingProduct())
        XCTAssertTrue(Store.shared.owned.contains(Plan.lifetime))
        XCTAssertEqual(state, "lifetime")
        XCTAssertEqual(plan, "founding")
        XCTAssertEqual(Store.shared.status()["entitled"] as? Bool, true)
    }

    func testARefundTakesItAway() async throws {
        try skipUnlessPurchasesAreLocal()
        await Store.shared.buy(try await foundingProduct())
        XCTAssertEqual(state, "lifetime")
        let t = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == Plan.lifetime })
        try session.refundTransaction(identifier: t.identifier)
        await Store.shared.refresh()
        XCTAssertFalse(Store.shared.owned.contains(Plan.lifetime))
        XCTAssertNotEqual(state, "lifetime")
    }
}
