const CACHE_NAME = "po-barteru-shell-v1";
self.addEventListener("install", event => {
  event.waitUntil(self.skipWaiting());
});
self.addEventListener("activate", event => {
  event.waitUntil(self.clients.claim());
});
self.addEventListener("push", event => {
  let payload = {};
  try { payload = event.data ? event.data.json() : {}; }
  catch (_) { payload = { body: event.data ? event.data.text() : "" }; }
  const title = payload.title || "ПО БАРТЕРУ";
  const options = {
    body: payload.body || "У вас новое событие",
    icon: "/logo.webp?v=1",
    badge: "/logo.webp?v=1",
    tag: payload.tag || payload.conversation_id || payload.proposal_id || "po-barteru-notification",
    renotify: false,
    data: { url: payload.url || "/", conversation_id: payload.conversation_id || null, proposal_id: payload.proposal_id || null }
  };
  event.waitUntil(self.registration.showNotification(title, options));
});
self.addEventListener("notificationclick", event => {
  event.notification.close();
  const target = new URL(event.notification.data && event.notification.data.url || "/", self.location.origin).href;
  event.waitUntil((async () => {
    const clientsList = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const client of clientsList) {
      if (client.url.startsWith(self.location.origin) && "focus" in client) {
        await client.focus();
        if ("navigate" in client && client.url !== target) await client.navigate(target);
        return;
      }
    }
    if (self.clients.openWindow) await self.clients.openWindow(target);
  })());
});
