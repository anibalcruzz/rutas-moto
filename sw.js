// Rutas Moteras: funciona sin conexión.
// - La app (index, iconos, Leaflet) se guarda al instalar.
// - index.html: primero red (para recibir rutas nuevas), si no hay conexión, la copia guardada.
// - Trozos de mapa: se guardan los que ya has visto, para tenerlos sin cobertura.
var APP = "rutas-app-v1";
var TILES = "rutas-tiles-v1";
var MAX_TILES = 3000;
var SHELL = [
  "./", "./index.html", "./manifest.webmanifest", "./icon-192.png", "./icon-512.png",
  "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css",
  "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js"
];

self.addEventListener("install", function (e) {
  e.waitUntil(caches.open(APP).then(function (c) { return c.addAll(SHELL); }).then(function () { return self.skipWaiting(); }));
});

self.addEventListener("activate", function (e) {
  e.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.filter(function (k) { return k !== APP && k !== TILES; }).map(function (k) { return caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});

function trimTiles() {
  return caches.open(TILES).then(function (c) {
    return c.keys().then(function (keys) {
      if (keys.length <= MAX_TILES) return;
      return Promise.all(keys.slice(0, keys.length - MAX_TILES).map(function (k) { return c.delete(k); }));
    });
  });
}

self.addEventListener("fetch", function (e) {
  var req = e.request;
  if (req.method !== "GET") return;
  var url = new URL(req.url);

  // Página principal: red primero
  if (req.mode === "navigate") {
    e.respondWith(fetch(req).then(function (res) {
      var copy = res.clone();
      caches.open(APP).then(function (c) { c.put("./index.html", copy); });
      return res;
    }).catch(function () { return caches.match("./index.html"); }));
    return;
  }

  // Mapa base: caché primero
  if (url.hostname === "server.arcgisonline.com") {
    e.respondWith(caches.open(TILES).then(function (c) {
      return c.match(req).then(function (hit) {
        if (hit) return hit;
        return fetch(req).then(function (res) {
          if (res.ok || res.type === "opaque") { c.put(req, res.clone()); trimTiles(); }
          return res;
        });
      });
    }));
    return;
  }

  // Archivos de la app y Leaflet: caché primero
  if (url.origin === location.origin || url.hostname === "cdnjs.cloudflare.com") {
    e.respondWith(caches.match(req).then(function (hit) {
      return hit || fetch(req).then(function (res) {
        if (res.ok) { var copy = res.clone(); caches.open(APP).then(function (c) { c.put(req, copy); }); }
        return res;
      });
    }));
  }
  // El resto (trazados, bares) va siempre a la red.
});
