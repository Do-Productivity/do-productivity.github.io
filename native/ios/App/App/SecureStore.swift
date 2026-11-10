import Foundation
import Capacitor
import Security

/// The few things in Do. that are worth stealing — the GitHub sync token,
/// the cloud session and its refresh token, the calendar feed token, the
/// Microsoft refresh token — kept in the iOS Keychain instead of in the web
/// view's localStorage.
///
/// What this buys, stated exactly:
///
///  - localStorage is a file in the app container. It goes into device
///    backups, and an unencrypted backup on somebody's laptop is the token in
///    plain text. Keychain items stored `ThisDeviceOnly` never leave the
///    phone in any backup and are never synced to iCloud Keychain.
///  - They are encrypted with a key held by the Secure Enclave and are
///    unreadable until the phone has been unlocked once after a restart.
///
/// What it does not buy: script running inside the web view can still ask
/// this plugin for a value, because the app's own script has to. The defence
/// against injected script is the Content-Security-Policy, not this. This
/// closes the at-rest and backup routes; the policy closes the other one.
///
/// Keys are held to the app's own prefix, so the bridge cannot be used as a
/// general-purpose Keychain reader.
@objc(SecureStorePlugin)
public class SecureStorePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SecureStorePlugin"
    public let jsName = "SecureStore"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getAll", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "set", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "remove", returnType: CAPPluginReturnPromise)
    ]

    static let service = "com.ahmedmohsen.todolist.secrets"
    static let prefix = "dia_todo_"
    /// A token is a few hundred bytes. Anything far past that is not a token.
    static let maxBytes = 64 * 1024

    private func allowed(_ key: String?) -> String? {
        guard let key = key, key.hasPrefix(Self.prefix), key.count <= 64,
              key.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil
        else { return nil }
        return key
    }

    @objc func getAll(_ call: CAPPluginCall) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        var items: [String: String] = [:]
        if status == errSecSuccess, let rows = out as? [[String: Any]] {
            for row in rows {
                guard let key = row[kSecAttrAccount as String] as? String,
                      let data = row[kSecValueData as String] as? Data,
                      let value = String(data: data, encoding: .utf8) else { continue }
                items[key] = value
            }
        } else if status != errSecItemNotFound {
            call.reject("Keychain read failed (\(status))")
            return
        }
        call.resolve(["items": items])
    }

    @objc func set(_ call: CAPPluginCall) {
        guard let key = allowed(call.getString("key")),
              let value = call.getString("value"),
              let data = value.data(using: .utf8), data.count <= Self.maxBytes else {
            call.reject("Not a key or value this store keeps")
            return
        }
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key
        ]
        // Delete-then-add rather than update: an update keeps the old item's
        // accessibility class, and the class is the point.
        SecItemDelete(match as CFDictionary)
        var add = match
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess { call.resolve() }
        else { call.reject("Keychain write failed (\(status))") }
    }

    @objc func remove(_ call: CAPPluginCall) {
        guard let key = allowed(call.getString("key")) else {
            call.reject("Not a key this store keeps")
            return
        }
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(match as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { call.resolve() }
        else { call.reject("Keychain delete failed (\(status))") }
    }
}
