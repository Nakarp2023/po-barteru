import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const root = new URL("../", import.meta.url);
const read = path => readFileSync(new URL(path, root), "utf8");
const html = read("index.html");
const notificationMigration = read("supabase/migrations/20261101201440_allow_saved_search_match_notifications.sql");
const supportFunction = read("supabase/functions/support-telegram-notify/index.ts");
const setupFunction = read("supabase/functions/support-telegram-setup/index.ts");

assert.match(notificationMigration, /saved_search_match/, "notification constraint must allow saved-search match events");
assert.match(html, /data-listing="\'+esc\(n\.listing_id\|\|\'\'\)/, "notification cards must retain the related listing id");
assert.match(html, /btn\.dataset\.type==="saved_search_match"[\s\S]{0,500}openListingDetails\(mapped\[0\]\)/, "saved-search notification must open its active listing");
assert.match(supportFunction, /po-barteru-no-gestures-staging\.onrender\.com/, "support function must allow current staging origin");
assert.match(supportFunction, /po-barteru\.onrender\.com/, "support function must allow production origin");
assert.doesNotMatch(supportFunction, /po-barteru-stable-navigation-preview/, "obsolete preview origin must not remain in support CORS");
assert.match(supportFunction, /auth\.getUser\(token\)/, "support notifications must validate the caller's user token");
assert.match(setupFunction, /status:\s*410/, "public Telegram webhook setup endpoint must be disabled");
console.log("Staging technical readiness checks passed (8 assertions).");
