import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};
const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: corsHeaders });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply(405, { error: "method_not_allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return reply(503, { error: "server_not_configured" });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return reply(401, { error: "authorization_required" });

  let body: { listing_id?: unknown };
  try { body = await req.json(); } catch { return reply(400, { error: "invalid_json" }); }
  const listingId = typeof body.listing_id === "string" ? body.listing_id : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(listingId)) {
    return reply(400, { error: "invalid_listing_id" });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  const user = authData?.user;
  if (authError || !user) return reply(401, { error: "invalid_session" });

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Enforce ownership on the server; never trust a user_id supplied by the browser.
  const { data: listing, error: lookupError } = await admin
    .from("listings").select("id,user_id").eq("id", listingId).maybeSingle();
  if (lookupError) return reply(500, { error: "listing_lookup_failed" });
  if (!listing) return reply(404, { error: "listing_not_found" });
  if (listing.user_id !== user.id) return reply(403, { error: "listing_not_owned" });

  // Preserve exchange, paid-promotion, and moderation history by archiving related listings.
  // Direct deletion could cascade-delete exchange proposals/reviews, promotions, or reports.
  const { data: relatedProposals, error: proposalLookupError } = await admin
    .from("exchange_proposals")
    .select("id")
    .or(`listing_id.eq.${listingId},offered_listing_id.eq.${listingId}`)
    .limit(1);
  if (proposalLookupError) {
    console.error("related proposal lookup failed", proposalLookupError.message);
    return reply(500, { error: "exchange_history_lookup_failed" });
  }

  const { data: relatedPromotions, error: promotionLookupError } = await admin
    .from("listing_promotions")
    .select("id")
    .eq("listing_id", listingId)
    .limit(1);
  if (promotionLookupError) {
    console.error("related promotion lookup failed", promotionLookupError.message);
    return reply(500, { error: "promotion_history_lookup_failed" });
  }

  const { data: relatedReports, error: reportLookupError } = await admin
    .from("reports")
    .select("id")
    .eq("listing_id", listingId)
    .limit(1);
  if (reportLookupError) {
    console.error("related report lookup failed", reportLookupError.message);
    return reply(500, { error: "report_history_lookup_failed" });
  }

  if (relatedProposals?.length || relatedPromotions?.length || relatedReports?.length) {
    const { data: archived, error: archiveError } = await admin
      .from("listings")
      .update({ status: "archived" })
      .eq("id", listingId)
      .eq("user_id", user.id)
      .select("id")
      .maybeSingle();
    if (archiveError) {
      console.error("listing archive failed", archiveError.message);
      return reply(500, { error: "listing_archive_failed" });
    }
    if (!archived) return reply(409, { error: "listing_not_archived" });
    return reply(200, { ok: true, archived: true, deleted_id: archived.id });
  }

  // Only listings with no retained exchange, promotion, or report history are physically deleted.
  const { data: deleted, error: deleteError } = await admin
    .from("listings").delete().eq("id", listingId).eq("user_id", user.id).select("id").maybeSingle();
  if (deleteError) {
    console.error("listing delete failed", deleteError.message);
    return reply(500, { error: "listing_delete_failed" });
  }
  if (!deleted) return reply(409, { error: "listing_not_deleted" });
  return reply(200, { ok: true, archived: false, deleted_id: deleted.id });
});