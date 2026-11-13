// Rutas Moteras: funciona sin conexión con lo que ya se ha visto.
// - App y lugares.json: primero red (para recibir cambios y pins nuevos); sin conexión, la copia guardada.
// - Mapa, fotos y fuentes: primero la copia guardada (se van guardando los que ves).
// - Resúmenes de Wikipedia: primero red; sin conexión, el último guardado.
// - Rutas y servicios cercanos: siempre red.
var APP = "rutas-app-v9";
var TILES = "rutas-tiles-v2";   // v2: mapa en color (Esri World Topo); se borran las teselas grises de antes
var MEDIA = "rutas-media-v1";
var LIMITES = {};
LIMITES[TILES] = 4000;
LIMITES[MEDIA] = 600;
var SHELL = [
  "./", "./index.html", "./lugares.json", "./manifest.webmanifest", "./icon-192.png", "./icon-512.png",
  "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css",
  "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js"
];

self.addEventListener("install", function (e) {
  e.waitUntil(caches.open(APP).then(function (c) { return c.addAll(SHELL); }).then(function () { return self.skipWaiting(); }));
});
self.addEventListener("activate", function (e) {
  e.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.filter(function (k) { return [APP, TILES, MEDIA].indexOf(k) < 0; }).map(function (k) { return caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});

function recortar(nombre) {
  return caches.open(nombre).then(function (c) {
    return c.keys().then(function (keys) {
      var max = LIMITES[nombre];
      if (!max || keys.length <= max) return;
      return Promise.all(keys.slice(0, keys.length - max).map(function (k) { return c.delete(k); }));
    });
  });
}
function primeroRed(req, cache, clave) {
  return fetch(req).then(function (res) {
    if (res && (res.ok || res.type === "opaque")) { var copia = res.clone(); caches.open(cache).then(function (c) { c.put(clave || req, copia); }); }
    return res;
  }).catch(function () { return caches.match(clave || req); });
}
function primeroCache(req, cache) {
  return caches.match(req).then(function (hit) {
    return hit || fetch(req).then(function (res) {
      if (res && (res.ok || res.type === "opaque")) { var copia = res.clone(); caches.open(cache).then(function (c) { c.put(req, copia).then(function () { recortar(cache); }); }); }
      return res;
    });
  });
}

self.addEventListener("fetch", function (e) {
  var req = e.request;
  if (req.method !== "GET") return;
  var url = new URL(req.url);
  if (req.mode === "navigate") { e.respondWith(primeroRed(req, APP, "./index.html")); return; }
  if (url.origin === location.origin && /lugares\.json$/.test(url.pathname)) { e.respondWith(primeroRed(req, APP, "./lugares.json")); return; }
  if (url.hostname === "server.arcgisonline.com") { e.respondWith(primeroCache(req, TILES)); return; }
  if (url.hostname === "upload.wikimedia.org" || url.hostname === "thumb.wikimedia.org" || url.hostname === "fonts.gstatic.com" || url.hostname === "fonts.googleapis.com") { e.respondWith(primeroCache(req, MEDIA)); return; }
  if (url.hostname === "es.wikipedia.org" && url.pathname.indexOf("/api/rest_v1/page/summary/") === 0) { e.respondWith(primeroRed(req, MEDIA)); return; }
  if (url.origin === location.origin || url.hostname === "cdnjs.cloudflare.com") { e.respondWith(primeroCache(req, APP)); return; }
});
