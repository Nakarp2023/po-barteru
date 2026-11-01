import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedOrigins = new Set([
  "https://po-barteru-no-gestures-staging.onrender.com",
  "https://po-barteru.onrender.com",
]);
const corsHeaders = (origin: string | null): HeadersInit => ({
  ...(origin && allowedOrigins.has(origin) ? { "Access-Control-Allow-Origin": origin } : {}),
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
  "Vary": "Origin",
});
const json = (origin: string | null, body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
  });
const esc = (value: unknown) => String(value ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);
const categories: Record<string, string> = {
  account: "Аккаунт и вход", listing: "Объявление", exchange: "Обмен или сделка",
  payment: "Оплата и услуги", safety: "Безопасность или жалоба",
  technical: "Техническая проблема", other: "Другой вопрос",
};

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (origin && !allowedOrigins.has(origin)) return new Response("Forbidden", { status: 403, headers: { "Vary": "Origin" } });
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(origin) });
  if (req.method !== "POST") return json(origin, { error: "Method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN");
  const supportChatId = Deno.env.get("TELEGRAM_SUPPORT_CHAT_ID");
  if (!url || !serviceKey || !botToken || !supportChatId) {
    console.error("Support Telegram integration is missing server configuration");
    return json(origin, { error: "Support notifications are not configured" }, 503);
  }
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return json(origin, { error: "Unauthorized" }, 401);
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData.user) return json(origin, { error: "Unauthorized" }, 401);
  let input: { ticket_id?: string };
  try { input = await req.json(); } catch { return json(origin, { error: "Invalid JSON" }, 400); }
  if (!input.ticket_id || !/^[0-9a-f-]{36}$/i.test(input.ticket_id)) return json(origin, { error: "Invalid ticket_id" }, 400);
  const { data: ticket, error: ticketError } = await admin.from("support_tickets")
    .select("id,user_id,category,subject,message,created_at")
    .eq("id", input.ticket_id).eq("user_id", authData.user.id).maybeSingle();
  if (ticketError || !ticket) return json(origin, { error: "Ticket not found" }, 404);
  const body = [
    "🆕 <b>Новое обращение — ПО БАРТЕРУ</b>",
    "<b>Номер:</b> <code>" + esc(ticket.id) + "</code>",
    "<b>Тема:</b> " + esc(categories[ticket.category] || "Другой вопрос"),
    "<b>Заголовок:</b> " + esc(ticket.subject),
    "<b>Текст:</b>", esc(String(ticket.message).slice(0, 2800)), "",
    "<i>Чтобы ответить пользователю, ответьте реплаем на это сообщение. Ответ появится в личном кабинете.</i>",
  ].join("\n");
  const telegramResponse = await fetch("https://api.telegram.org/bot" + botToken + "/sendMessage", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ chat_id: supportChatId, text: body, parse_mode: "HTML", disable_web_page_preview: true }),
  });
  const result = await telegramResponse.json().catch(() => ({}));
  if (!telegramResponse.ok || !result.ok) {
    console.error("Telegram support delivery failed", result.error_code || telegramResponse.status);
    return json(origin, { error: "Could not notify support team" }, 502);
  }
  return json(origin, { ok: true });
});
