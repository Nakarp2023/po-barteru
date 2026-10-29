import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const uuidPattern = /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i;
const telegramApi = (token: string, method: string) => "https://api.telegram.org/bot" + token + "/" + method;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const expectedSecret = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") || "";
  const receivedSecret = req.headers.get("X-Telegram-Bot-Api-Secret-Token") || "";
  if (!expectedSecret || receivedSecret.length !== expectedSecret.length || receivedSecret !== expectedSecret) {
    return new Response("Forbidden", { status: 403 });
  }
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN");
  const supportChatId = Deno.env.get("TELEGRAM_SUPPORT_CHAT_ID");
  const allowedIds = (Deno.env.get("TELEGRAM_SUPPORT_USER_IDS") || "").split(",").map((v) => v.trim()).filter(Boolean);
  if (!url || !serviceKey || !botToken || !supportChatId || !allowedIds.length) {
    console.error("Support webhook is missing required server configuration");
    return new Response("Not configured", { status: 503 });
  }
  let update: any;
  try { update = await req.json(); } catch { return new Response("Invalid JSON", { status: 400 }); }
  const message = update?.message;
  if (!message || String(message.chat?.id) !== supportChatId || message.from?.is_bot) return new Response("ok");
  if (!allowedIds.includes(String(message.from?.id || ""))) {
    console.warn("Ignored Telegram support reply from an unapproved sender");
    return new Response("ok");
  }
  if (!message.reply_to_message?.text || typeof message.text !== "string") return new Response("ok");
  const match = message.reply_to_message.text.match(uuidPattern);
  const reply = message.text.trim();
  if (!match || reply.length < 1 || reply.length > 5000 || reply.startsWith("/")) return new Response("ok");
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: ticket, error: lookupError } = await admin.from("support_tickets").select("id,status").eq("id", match[0]).maybeSingle();
  if (lookupError || !ticket) {
    console.error("Support reply references an unknown ticket", lookupError?.message || "not found");
    return new Response("ok");
  }
  const now = new Date().toISOString();
  const { error: updateError } = await admin.from("support_tickets").update({
    support_reply: reply, status: "answered", replied_at: now, updated_at: now,
  }).eq("id", ticket.id);
  if (updateError) {
    console.error("Could not save support reply", updateError.message);
    return new Response("Temporary database error", { status: 500 });
  }
  await fetch(telegramApi(botToken, "sendMessage"), {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      chat_id: supportChatId, reply_to_message_id: message.message_id,
      text: "✅ Ответ сохранён в обращении " + ticket.id.slice(0, 8) + ". Он появится у пользователя в разделе «Мои обращения».",
      disable_web_page_preview: true,
    }),
  }).catch((error) => console.error("Could not send Telegram acknowledgement", error));
  return new Response("ok");
});