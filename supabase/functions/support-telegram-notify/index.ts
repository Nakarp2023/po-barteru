import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "https://po-barteru.onrender.com",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const esc = (value: unknown) => String(value ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);
const categories: Record<string, string> = {
  account: "Аккаунт и вход", listing: "Объявление", exchange: "Обмен или сделка",
  payment: "Оплата и услуги", safety: "Безопасность или жалоба",
  technical: "Техническая проблема", other: "Другой вопрос",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN");
  const supportChatId = Deno.env.get("TELEGRAM_SUPPORT_CHAT_ID");
  if (!url || !serviceKey || !botToken || !supportChatId) {
    console.error("Support Telegram integration is missing server configuration");
    return json({ error: "Support notifications are not configured" }, 503);
  }
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Unauthorized" }, 401);
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "Unauthorized" }, 401);
  let input: { ticket_id?: string };
  try { input = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  if (!input.ticket_id || !/^[0-9a-f-]{36}$/i.test(input.ticket_id)) return json({ error: "Invalid ticket_id" }, 400);
  const { data: ticket, error: ticketError } = await admin.from("support_tickets")
    .select("id,user_id,category,subject,message,created_at")
    .eq("id", input.ticket_id).eq("user_id", authData.user.id).maybeSingle();
  if (ticketError || !ticket) return json({ error: "Ticket not found" }, 404);
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
    return json({ error: "Could not notify support team" }, 502);
  }
  return json({ ok: true });
});