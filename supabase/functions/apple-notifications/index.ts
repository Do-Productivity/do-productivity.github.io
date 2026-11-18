// App Store Server Notifications (version 2): Apple tells us about refunds.
//
// A referred friend's purchase that is refunded or revoked must never earn
// the referrer a free month, so on REFUND or REVOKE the conversion is marked
// refunded. Everything else Apple sends is acknowledged and ignored: Do.
// decides who has paid on the phone, from StoreKit, not from here.
//
// Its address goes in App Store Connect → App Information → App Store Server
// Notifications → Production Server URL. Deploy with JWT checking off (Apple
// does not send one); Apple's signature is the check:
//   supabase functions deploy apple-notifications --no-verify-jwt

import "npm:reflect-metadata@0.2.2";
import * as x509 from "npm:@peculiar/x509@3.1.0";
import { verifyAppleJws, BUNDLE_ID } from "../_shared/apple-core.js";

const REFUNDS = ["REFUND", "REVOKE"];

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("", { status: 405 });
  let note;
  try {
    const body = await req.json();
    note = await verifyAppleJws(String(body.signedPayload || ""), { x509 });
  } catch (_) {
    return new Response("", { status: 400 });
  }
  const data = note.data || {};
  if (data.bundleId !== BUNDLE_ID) return new Response("", { status: 200 });
  if (!REFUNDS.includes(note.notificationType) || !data.signedTransactionInfo) {
    return new Response("", { status: 200 });
  }
  let t;
  try { t = await verifyAppleJws(String(data.signedTransactionInfo), { x509 }); }
  catch (_) { return new Response("", { status: 400 }); }

  const url = Deno.env.get("SUPABASE_URL")!;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const res = await fetch(url + "/rest/v1/rpc/referral_refund", {
    method: "POST",
    headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" },
    body: JSON.stringify({ otx: String(t.originalTransactionId || "") }),
  });
  // a failure is answered with an error so Apple tries again later
  return new Response("", { status: res.ok ? 200 : 500 });
});
