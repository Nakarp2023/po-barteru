# Telegram support integration — ПО БАРТЕРУ

The support ticket form remains the canonical record in Supabase. Telegram is the private staff inbox and reply channel; customers see replies in their account under “Мои обращения”.

## Security model

- Never put the Telegram bot token or Supabase service-role key in `index.html`, a public repository secret, or a user-facing message.
- Configure secrets in Supabase Dashboard → Project Settings → Edge Functions / Secrets (menu wording may vary).
- `support-telegram-notify` requires a valid Supabase user JWT and verifies that the ticket belongs to that user.
- `support-telegram-webhook` disables platform JWT verification because Telegram cannot provide a Supabase JWT, but validates Telegram's `X-Telegram-Bot-Api-Secret-Token` header itself.
- Only Telegram user IDs listed in `TELEGRAM_SUPPORT_USER_IDS` can reply to tickets.
- Staff must reply directly to the bot's original ticket message in the private support group. The reply is saved to the ticket and appears in the user's account.
- Keep the support group private and only add trusted staff. Do not ask customers to send passwords, one-time codes, or full card details.

## Required secrets

Set these secrets for the Supabase project:

- `TELEGRAM_BOT_TOKEN`: token created by `@BotFather`. Treat it like a password.
- `TELEGRAM_SUPPORT_CHAT_ID`: ID of the private staff group (usually a negative number for a group/supergroup).
- `TELEGRAM_WEBHOOK_SECRET`: random 32+ character value containing only A-Z, a-z, 0-9, underscore or hyphen. Use a password manager or cryptographically secure generator.
- `TELEGRAM_SUPPORT_USER_IDS`: comma-separated numeric Telegram user IDs of approved staff, e.g. `12345678,23456789`. Do not use usernames for authorization.

Supabase supplies `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions. Confirm these built-in environment values exist in the project before testing.

## One-time Telegram setup

1. Create a bot through `@BotFather`; set its display name and username. Keep the token private.
2. Create a private Telegram group for support staff, add the bot, and make sure the bot can send messages. The bot should remain in default privacy mode; staff replies to the bot's original ticket messages are visible to it.
3. Find the group chat ID and numeric Telegram user IDs for every staff member. Verify these IDs independently before adding them to the secret.
4. Set the required secrets above in Supabase.
5. Register the webhook using the exact endpoint below. Run this command in a trusted terminal after replacing placeholders locally; never commit a filled-in command or paste the token into GitHub issues/chat.

```sh
curl -sS -X POST "https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/setWebhook" \
  -H "Content-Type: application/json" \
  --data '{"url":"https://qxsnjksepzmpsifpxyea.supabase.co/functions/v1/support-telegram-webhook","secret_token":"<TELEGRAM_WEBHOOK_SECRET>","allowed_updates":["message"]}'
```

Check webhook status in the same trusted terminal:

```sh
curl -sS "https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/getWebhookInfo"
```

Do not share the returned token or any secret values. If the bot token was ever exposed, rotate it with `@BotFather` before production use.

## End-to-end acceptance test

1. Sign in to ПО БАРТЕРУ and submit a test support ticket with non-sensitive content.
2. Confirm the ticket is saved under “Мои обращения” and the private support group receives one notification.
3. In the support group, use Telegram Reply on that bot notification and send a short test response.
4. Confirm the bot acknowledges the saved response and the same response appears under the ticket in the user's account after pressing “Обновить”.
5. Confirm a non-approved Telegram user cannot update tickets; confirm a regular user cannot invoke notifications for another user's ticket.
6. Remove the test ticket if appropriate through the controlled admin workflow. Never use production payment or exchange records as test data.

## Current deployment note

The Edge Functions are deployed, but Telegram delivery is not active until all required secrets are configured and the webhook is registered. The frontend notification call is staged in the feature branch until the complete integration is reviewed and merged.
