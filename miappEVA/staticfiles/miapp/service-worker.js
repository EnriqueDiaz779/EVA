// --- EVA Service Worker Mejorado ---
// Cache + notificaciones con acciones
const CACHE_NAME = "eva-cache-v3";
const CORE_ASSETS = ["/", "/manifest.json"];

// === INSTALACIÓN ===
self.addEventListener("install", (event) => {
  console.log("📦 Instalando EVA Service Worker...");
  event.waitUntil(caches.open(CACHE_NAME).then(c => c.addAll(CORE_ASSETS)));
  self.skipWaiting();
});

// === ACTIVACIÓN ===
self.addEventListener("activate", (event) => {
  console.log("⚡ Activando EVA Service Worker...");
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.map(k => (k !== CACHE_NAME ? caches.delete(k) : null)))
    )
  );
  self.clients.claim();
});

// === ESTRATEGIA NETWORK-FIRST ===
self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;

  event.respondWith(
    fetch(req)
      .then(res => {
        const clone = res.clone();
        caches.open(CACHE_NAME).then(c => c.put(req, clone));
        return res;
      })
      .catch(() => caches.match(req))
  );
});

// === MOSTRAR NOTIFICACIÓN DESDE MENSAJE ===
self.addEventListener("message", async (event) => {
  const data = event.data || {};
  if (data.type !== "SHOW_NOTIFICATION") return;

  const title = data.title || "⏰ EVA";
  const options = {
    body: data.body || "Tienes un aviso.",
    icon: "/static/miapp/icons/icon-192.png",
    badge: "/static/miapp/icons/icon-192.png",
    vibrate: [200, 100, 200],
    tag: data.tag || "eva-alert",
    requireInteraction: true,
    data: {
      url: "/",
      id: data.id || null,
    },
    actions: [
      { action: "tomada", title: "✅ Tomada", icon: "/static/miapp/icons/check.png" },
      { action: "omitir", title: "🔁 Omitir 5 min", icon: "/static/miapp/icons/repetir.png" }
    ]
  };

  console.log("🔔 Mostrando notificación EVA:", title);
  await self.registration.showNotification(title, options);
});

// === CUANDO EL USUARIO INTERACTÚA CON LA NOTIFICACIÓN ===
self.addEventListener("notificationclick", (event) => {
  console.log("👆 Clic en notificación:", event.action);
  event.notification.close();
  const { action, notification } = event;
  const id = notification.data?.id;

  if (action === "tomada" && id) {
    // Marca la alarma como entregada
    event.waitUntil(marcarEntregada(id));
    return;
  }

  if (action === "omitir" && id) {
    // Reprograma la alarma a +5 minutos
    event.waitUntil(reprogramarAlarma(id));
    return;
  }

  // Si no se presionó ninguna acción específica → abrir o enfocar la app
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if (client.url.includes("/") && "focus" in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow(notification.data?.url || "/");
    })
  );
});

async function marcarEntregada(id) {
  try {
    await fetch("/alarmas/marcar-entregada/", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ id })
    });
    console.log(`✅ Alarma #${id} marcada como entregada`);
  } catch (err) {
    console.error("❌ Error marcando entregada:", err);
  }
}

async function reprogramarAlarma(id) {
  try {
    const resp = await fetch("/alarmas/reprogramar/", {   // ✅ ruta correcta
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ id })
    });
    const data = await resp.json();
    console.log(`🔁 Alarma #${id} reprogramada +5 min → ${data.nueva_hora}`);
    self.registration.showNotification("🔁 EVA", {
      body: "Alarma reprogramada para " + data.nueva_hora,
      icon: "/static/miapp/icons/repetir.png",
      vibrate: [150, 100, 150],
      silent: true
    });
  } catch (err) {
    console.error("❌ Error reprogramando alarma:", err);
  }
}

