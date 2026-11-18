// Records a referred friend's subscription, after checking Apple signed it.
//
// The app sends { jws, t }: the transaction exactly as StoreKit gave it, and
// the sha256 of the token the friend's device made when they entered a
// referral code. Nothing the app says is believed except what Apple signed.
//
// Deploy with JWT checking off (the app calls it with the publishable key,
// which is not a JWT); the Apple signature is the check:
//   supabase functions deploy referral-convert --no-verify-jwt
// Set REFERRAL_ALLOW_SANDBOX=1 while TestFlight testers should see the flow;
// their purchases are recorded as test-only and never given a real code.

import "npm:reflect-metadata@0.2.2";
import * as x509 from "npm:@peculiar/x509@3.1.0";
import { verifyAppleJws, checkTransaction } from "../_shared/apple-core.js";

const ORIGINS = ["capacitor://localhost", "https://do-productivity.github.io"];

function cors(req: Request) {
  const o = req.headers.get("origin") || "";
  return {
    "Access-Control-Allow-Origin": ORIGINS.includes(o) ? o : ORIGINS[1],
    "Access-Control-Allow-Headers": "apikey, authorization, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function reply(req: Request, status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(req), "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req) });
  if (req.method !== "POST") return reply(req, 405, { ok: false, reason: "method" });

  let body: { jws?: string; t?: string };
  try { body = await req.json(); } catch (_) { return reply(req, 400, { ok: false, reason: "bad" }); }
  const t = String(body.t || "");
  if (!/^[0-9a-f]{64}$/.test(t)) return reply(req, 400, { ok: false, reason: "bad" });

  let sale;
  try {
    const payload = await verifyAppleJws(String(body.jws || ""), { x509 });
    sale = checkTransaction(payload, { allowSandbox: Deno.env.get("REFERRAL_ALLOW_SANDBOX") === "1" });
  } catch (e) {
    const why = (e as Error & { refused?: boolean }).refused ? (e as Error).message : "could not check";
    return reply(req, 422, { ok: false, reason: why });
  }

  const url = Deno.env.get("SUPABASE_URL")!;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const res = await fetch(url + "/rest/v1/rpc/referral_convert", {
    method: "POST",
    headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" },
    body: JSON.stringify({ t, otx: sale.otx, product: sale.product, paid: sale.paid, sandbox: sale.sandbox }),
  });
  if (!res.ok) return reply(req, 502, { ok: false, reason: "database" });
  return reply(req, 200, await res.json());
});
