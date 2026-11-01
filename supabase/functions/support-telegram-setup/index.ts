import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// This administrative endpoint was previously public and could change the
// Telegram bot webhook. Webhook configuration is intentionally disabled here;
// manage it only through a trusted, authenticated deployment workflow.
Deno.serve((req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }
  return Response.json(
    { error: "Telegram webhook setup is disabled for this project." },
    { status: 410, headers: { "Cache-Control": "no-store" } },
  );
});
