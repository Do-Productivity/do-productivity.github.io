// Checking that a purchase really came from Apple.
//
// StoreKit 2 hands the app each transaction as a JWS: a JSON payload signed
// by a key whose certificate chains up to Apple Root CA - G3. Anybody can
// write a JSON payload; only Apple can sign one that chains to that root.
// So a referral is counted only when:
//   1. the JWS carries a three-certificate chain (leaf, intermediate, root);
//   2. the root is byte-for-byte Apple Root CA - G3 (pinned by its SHA-256);
//   3. each certificate is signed by the next, and was valid when Apple
//      signed the transaction;
//   4. the leaf and intermediate carry Apple's own App Store markers;
//   5. the JWS signature checks out against the leaf's public key;
//   6. the payload is our app, one of our two subscriptions, bought (not
//      shared by Family Sharing), not refunded or revoked, and paid for.
// This mirrors Apple's own App Store Server Library (SignedDataVerifier),
// written against WebCrypto so the same file runs in the Supabase Edge
// Function (Deno) and in the tests (Node).
//
// The certificate library (@peculiar/x509) is passed in, not imported, so
// each side loads it its own way.

// SHA-256 of Apple Root CA - G3 (AppleRootCA-G3.cer, apple.com/certificateauthority).
// Check against the certificate Apple publishes before deploying.
export const APPLE_ROOT_G3_SHA256 = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

// Apple's markers: an App Store receipt-signing leaf, and the Apple
// Worldwide Developer Relations intermediate.
const LEAF_OID = "1.2.840.113635.100.6.11.1";
const INTERMEDIATE_OID = "1.2.840.113635.100.6.2.1";

export const BUNDLE_ID = "io.github.do-productivity.do";
export const PRODUCTS = ["io.github.doproductivity.do.monthly", "io.github.doproductivity.do.yearly"];

function fromB64(s) {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function fromB64url(s) {
  const t = s.replace(/-/g, "+").replace(/_/g, "/");
  return fromB64(t + "=".repeat((4 - (t.length % 4)) % 4));
}
function hex(buf) {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function fail(why) { const e = new Error(why); e.refused = true; throw e; }

/** Returns the payload of a JWS that Apple signed; throws (e.refused) otherwise. */
export async function verifyAppleJws(jws, { x509, rootSha256 = APPLE_ROOT_G3_SHA256, now = Date.now() } = {}) {
  if (typeof jws !== "string" || jws.length > 20000) fail("not a signed transaction");
  const parts = jws.split(".");
  if (parts.length !== 3) fail("not a signed transaction");
  let header, payload;
  try {
    header = JSON.parse(new TextDecoder().decode(fromB64url(parts[0])));
    payload = JSON.parse(new TextDecoder().decode(fromB64url(parts[1])));
  } catch (_) { fail("not a signed transaction"); }
  if (header.alg !== "ES256") fail("unexpected signature type");
  if (!Array.isArray(header.x5c) || header.x5c.length !== 3) fail("no certificate chain");

  let certs;
  try { certs = header.x5c.map((b) => new x509.X509Certificate(fromB64(b))); }
  catch (_) { fail("unreadable certificate"); }
  const [leaf, mid, root] = certs;

  const fp = hex(await crypto.subtle.digest("SHA-256", root.rawData));
  if (fp !== rootSha256) fail("not signed by Apple");

  // valid when Apple signed it (as Apple's own library checks, offline)
  const at = new Date(typeof payload.signedDate === "number" ? payload.signedDate : now);
  for (const c of certs) {
    if (at < c.notBefore || at > c.notAfter) fail("certificate not valid at signing time");
  }
  if (!leaf.getExtension(LEAF_OID)) fail("not an App Store certificate");
  if (!mid.getExtension(INTERMEDIATE_OID)) fail("not Apple's intermediate");
  const bc = mid.getExtension(x509.BasicConstraintsExtension);
  if (!bc || !bc.ca) fail("intermediate is not a certificate authority");

  if (!(await mid.verify({ publicKey: root, signatureOnly: true }))) fail("broken certificate chain");
  if (!(await leaf.verify({ publicKey: mid, signatureOnly: true }))) fail("broken certificate chain");

  const key = await leaf.publicKey.export({ name: "ECDSA", namedCurve: "P-256" }, ["verify"]);
  const good = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" }, key,
    fromB64url(parts[2]), new TextEncoder().encode(parts[0] + "." + parts[1]));
  if (!good) fail("signature does not match");
  return payload;
}

/** Is this transaction a real, paid purchase of one of our subscriptions? */
export function checkTransaction(t, { allowSandbox = false } = {}) {
  if (!t || typeof t !== "object") fail("no transaction");
  if (t.bundleId !== BUNDLE_ID) fail("another app");
  if (!PRODUCTS.includes(t.productId)) fail("not a subscription");
  if (t.type !== "Auto-Renewable Subscription") fail("not a subscription");
  if (t.revocationDate) fail("refunded or revoked");
  if (t.inAppOwnershipType && t.inAppOwnershipType !== "PURCHASED") fail("shared, not bought");
  // a free month from an offer code, or any other zero-price start, is not a sale
  if (typeof t.price === "number" && t.price <= 0) fail("not paid");
  const sandbox = t.environment !== "Production";
  if (sandbox && !allowSandbox) fail("test purchase");
  const otx = String(t.originalTransactionId || "");
  if (!/^[0-9]{1,24}$/.test(otx)) fail("no transaction id");
  const paid = Number(t.originalPurchaseDate || t.purchaseDate);
  if (!Number.isFinite(paid) || paid <= 0) fail("no purchase date");
  return { otx, product: t.productId, paid: Math.round(paid), sandbox };
}
