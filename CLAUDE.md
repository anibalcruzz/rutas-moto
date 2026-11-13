# Rutas Moteras

App web instalable (PWA) para usar en la moto: mapa de España con rutas, pueblos, monumentos, paisajes y lugares históricos; tarjeta con datos de cada sitio; navegación propia con voz; progreso de lo hecho.
Publicada con GitHub Pages desde la rama `main`: https://anibalcruzz.github.io/rutas-moto/

## Lo que quiere el usuario (respetar siempre)
- Diseño **blanco, elegante y minimalista**. Nada de datos que no hagan falta.
- **Solo la navegación de la app**: no añadir enlaces a Google Maps, exportar GPX ni compartir rutas con otras apps.
- La usa en una **Galaxy Tab A (2016)** montada en la moto (Android antiguo, GPU modesta): todo debe ser ligero y fluido. Los pins se dibujan en canvas (`L.circleMarker` con `L.canvas`), nunca como iconos HTML.
- Se escribe en español, en tono claro y directo.

## Archivos
| Archivo | Qué es |
|---|---|
| `index.html` | Toda la app (estilos y código). Capas registradas en `CAPAS`. |
| `lugares.json` | **Los datos**: un lugar por línea. Es lo único que hay que tocar para añadir pins. |
| `sw.js` | Modo sin conexión. Sube la versión de `APP` cuando cambie `index.html`. |
| `manifest.webmanifest`, `icon-*.png` | Instalación como app. |
| `tools/*.ps1` | Herramientas de datos (PowerShell 5.1, guardadas en UTF-8 **con BOM**). |
| `datos/` | Listas recibidas tal cual, copias e informes de las herramientas. |

## Qué necesita cada pin (esquema de `lugares.json`)
Obligatorios (los aporta el usuario):
- `id` número único (los del usuario empiezan en 1; las rutas propias de la app usan 1001+).
- `capa`: `carreteras_puertos`, `pueblos_bonitos`, `monumentos`, `paisajes_naturales`, `historia`. Una capa nueva funciona sola con color neutro; para darle nombre y color, añádela a `CAPAS` en `index.html`.
- `nombre`, `lat`, `lon`.

Recomendados (los aporta el usuario): `tipo` (texto corto, p. ej. "Pueblo más bonito"), `lugar`, `comunidad`, `descripcion` (texto propio; si falta, la tarjeta muestra el resumen de Wikipedia), `unesco` (true).

Rutas: un lugar con `recorrido` (lista ordenada de `{nombre, lat, lon}`, mínimo 2) se convierte en ruta navegable con barra de progreso y marcado automático al completar el 80 %. `lat`/`lon` del lugar es dónde se dibuja el pin (p. ej. el puerto). Opcionales: `km_aprox`, `altitud_m`.

Investigados (los rellenan las herramientas; no inventarlos a mano):
- `wiki`: título del artículo en es.wikipedia (foto y resumen de la tarjeta). `""` = buscado y sin artículo.
- `wikidata`, `habitantes` + `habitantes_anio`, `altitud_m` (si faltaba), `epoca` (p. ej. "s. XIII"), `estilo`, `proteccion` + `proteccion_anio`, `superficie_km2`.
- `km_ruta`: km reales de la ruta en modo moto sin autovías.

La tarjeta muestra como mucho 4 datos (recorrido, altitud, habitantes, origen, superficie, estilo, protección), la distancia desde tu posición, servicios cercanos (comer/tomar algo y gasolinera; en rutas, paradas a lo largo del recorrido) y los botones Ir / Hecho / Guardar.

## Cómo añadir pins nuevos
1. Guarda la lista en `datos/recibidos-N.json` con el formato `{ "lugares": [ ... ] }` y ids que no existan.
2. `powershell -File tools\anadir-lugares.ps1 -Desde datos\recibidos-N.json` (valida campos obligatorios y no duplica ids).
3. Si hay rutas: `powershell -File tools\comprobar-rutas.ps1` → coloca los puertos en el nodo del puerto de OpenStreetMap y los pueblos en su centro, y guarda `km_ruta`. Revisa los avisos (medias vueltas, puntos lejos de la carretera).
4. `powershell -File tools\enriquecer.ps1` → busca el artículo de Wikipedia y los datos de Wikidata. Revisa `datos\informe-enriquecer.txt`; si un artículo es el equivocado, pon el título correcto en `wiki` y ejecuta `tools\enriquecer.ps1 -Ids N`.
5. Prueba en local y publica (`git push`): la tablet recibe los pins sola la próxima vez que abra la app con conexión.

Aunque no se ejecute el paso 4, la app busca sola el artículo de Wikipedia por cercanía y nombre (menos preciso).

## Servicios externos (sin clave)
- Mapa: Esri Light Gray Canvas (`server.arcgisonline.com`, máx. zoom nativo 16).
- Rutas: Valhalla de FOSSGIS (`valhalla1.openstreetmap.de`, modo `motorcycle`, `use_highways` 0 = sin autovías); OSRM público de reserva.
- Servicios cercanos: Overpass (3 servidores en cadena; a veces saturados, la tarjeta oculta la sección si fallan).
- Wikipedia REST (resumen y foto) y Wikidata (datos). Wikimedia solo sirve miniaturas de tamaños estándar (330, 500, 960 px…).
- Herramientas: Nominatim (máx. 1 petición/s) y OSRM `nearest`.

## Pendiente
- Lugares 312–520 de la lista del usuario: el mensaje llegó cortado en el 312. Cuando los envíe, seguir "Cómo añadir pins nuevos".
