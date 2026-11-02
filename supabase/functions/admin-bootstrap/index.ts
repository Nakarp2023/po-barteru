import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "https://po-barteru-no-gestures-staging.onrender.com",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const origin = req.headers.get("origin");
  if (origin && origin !== "https://po-barteru-no-gestures-staging.onrender.com") return json({ error: "Origin denied" }, 403);

  const expectedUid = "d153ce05-b2e8-4913-bb2d-8b69b63db2e4";
  const bootstrapSecret = Deno.env.get("ADMIN_BOOTSTRAP_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!bootstrapSecret || !supabaseUrl || !serviceKey) return json({ error: "Bootstrap is not configured" }, 503);

  const authHeader = req.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) return json({ error: "Authentication required" }, 401);
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const token = authHeader.slice(7);
  const { data: { user }, error: authError } = await admin.auth.getUser(token);
  if (authError || !user || user.id !== expectedUid) return json({ error: "Not permitted" }, 403);

  let body: { secret?: string };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  const supplied = body.secret;
  if (typeof supplied !== "string" || supplied.length < 32 || supplied.length > 256) return json({ error: "Invalid activation secret" }, 400);
  // Constant-time comparison for equal-length values.
  const a = new TextEncoder().encode(bootstrapSecret);
  const b = new TextEncoder().encode(supplied);
  let diff = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  if (diff !== 0) return json({ error: "Invalid activation secret" }, 403);

  // Claim once before granting. On failure release the claim for a safe retry.
  const { error: claimError } = await admin.from("admin_bootstrap_claims").insert({ user_id: expectedUid });
  if (claimError) return json({ error: "Bootstrap already consumed or unavailable" }, 409);
  const { error: updateError } = await admin.auth.admin.updateUserById(expectedUid, {
    app_metadata: { ...user.app_metadata, role: "admin" },
  });
  if (updateError) {
    await admin.from("admin_bootstrap_claims").delete().eq("user_id", expectedUid);
    return json({ error: "Role assignment failed" }, 500);
  }
  return json({ ok: true, message: "Administrator role assigned. Sign out and sign in again." });
});
