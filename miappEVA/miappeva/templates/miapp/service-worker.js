const CACHE_NAME = "eva-cache-v4";
const CORE_ASSETS = ["/", "/manifest.json"];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((c) => c.addAll(CORE_ASSETS)));
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.map((k) => (k !== CACHE_NAME ? caches.delete(k) : null))))
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;

  event.respondWith(
    fetch(req)
      .then((res) => {
        const clone = res.clone();
        caches.open(CACHE_NAME).then((c) => c.put(req, clone));
        return res;
      })
      .catch(() => caches.match(req))
  );
});

function buildNotification(payload = {}) {
  const rawKind = (payload.kind || payload.type || "alarma").toString().toLowerCase();
  const kind = rawKind === "show_notification" ? "alarma" : rawKind;
  const isAlarm = kind === "alarma";
  const isEmergency = kind === "emergencia";
  const isChat = kind === "chat";
  const isLocation = kind === "ubicacion";
  const title = payload.title || (isEmergency ? "SOS EVA" : (isChat ? "Chat EVA" : (isLocation ? "Ubicacion EVA" : "EVA")));

  const baseOptions = {
    body: payload.body || "Tienes un aviso.",
    icon: "/static/miapp/icons/icon-192.png",
    badge: "/static/miapp/icons/icon-192.png",
    tag: payload.tag || (isEmergency ? "eva-emergencia" : (isChat ? "eva-chat" : (isLocation ? "eva-ubicacion" : "eva-alert"))),
    requireInteraction: true,
    data: {
      url: payload.url || (isEmergency ? "/interfaz-cuidador/" : (isChat ? "/inicio/" : "/")),
      id: payload.id || null,
      kind,
      id_emergencia: payload.id_emergencia || null,
    },
    vibrate: isEmergency ? [300, 120, 300, 120, 300] : (isChat ? [120, 60, 120] : (isLocation ? [180, 80, 180] : [200, 100, 200])),
  };

  if (isAlarm) {
    baseOptions.actions = [
      { action: "tomada", title: "Tomada", icon: "/static/miapp/icons/check.png" },
      { action: "omitir", title: "Omitir 5 min", icon: "/static/miapp/icons/repetir.png" },
    ];
  } else if (isEmergency) {
    baseOptions.actions = [{ action: "ver", title: "Ver emergencia" }];
  } else if (isChat) {
    baseOptions.actions = [{ action: "abrir_chat", title: "Abrir chat" }];
  } else if (isLocation) {
    baseOptions.actions = [{ action: "ver_mapa", title: "Ver mapa" }];
  }

  return { title, options: baseOptions };
}

self.addEventListener("message", async (event) => {
  const data = event.data || {};
  if (data.type !== "SHOW_NOTIFICATION") return;
  const notif = buildNotification(data);
  await self.registration.showNotification(notif.title, notif.options);
});

self.addEventListener("push", (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    payload = {};
  }
  const notif = buildNotification(payload);
  event.waitUntil(self.registration.showNotification(notif.title, notif.options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const { action, notification } = event;
  const id = notification.data?.id;
  const kind = (notification.data?.kind || "").toLowerCase();

  if (kind !== "emergencia") {
    if (action === "tomada" && id) {
      event.waitUntil(marcarEntregada(id));
      return;
    }

    if (action === "omitir" && id) {
      event.waitUntil(reprogramarAlarma(id));
      return;
    }
  }

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      const targetUrl = notification.data?.url || "/";
      for (const client of clientList) {
        if (client.url.includes(targetUrl) && "focus" in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow(targetUrl);
      return null;
    })
  );
});

async function marcarEntregada(id) {
  try {
    await fetch("/alarmas/marcar-entregada/", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ id }),
    });
  } catch (_) {}
}

async function reprogramarAlarma(id) {
  try {
    const resp = await fetch("/alarmas/reprogramar/", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ id }),
    });
    const data = await resp.json();
    self.registration.showNotification("EVA", {
      body: "Alarma reprogramada para " + data.nueva_hora,
      icon: "/static/miapp/icons/repetir.png",
      vibrate: [150, 100, 150],
      silent: true,
    });
  } catch (_) {}
}
