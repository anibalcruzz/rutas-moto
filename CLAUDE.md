# Rutas Moteras

App web instalable (PWA) para usar en la moto: mapa de España con rutas, pueblos, monumentos, paisajes y lugares históricos; tarjeta con datos de cada sitio; navegación propia con voz; progreso de lo hecho.
Publicada con GitHub Pages desde la rama `main`: https://anibalcruzz.github.io/rutas-moto/

## Lo que quiere el usuario (respetar siempre)
- Diseño **alegre y limpio, estilo «cielo y montaña»** (cambiado a petición del usuario el 13/11/2026; antes era blanco y sobrio): tarjetas blancas muy redondeadas, azul `--blue` #2f6bff para actuar, naranja `--orange` #ff7a2f de acento (Improvisar, botón de ubicación), fondos azul claro, títulos en Poppins. Nada de datos que no hagan falta. El roadbook sigue en negro/grafito/lima.
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
- `wiki`: título del artículo en es.wikipedia (foto y resumen de la tarjeta). Si falta, la app lo busca sola por cercanía (la herramienta lo deja ausente cuando no encuentra nada).
- `wikidata`, `habitantes` + `habitantes_anio`, `altitud_m` (si faltaba), `epoca` (p. ej. "s. XIII"), `estilo`, `proteccion` + `proteccion_anio`, `superficie_km2`.
- `km_ruta`: km reales de la ruta en modo moto sin autovías.

La tarjeta muestra como mucho 4 datos (recorrido, altitud, habitantes, origen, superficie, estilo, protección), la distancia desde tu posición, servicios cercanos (comer/tomar algo y gasolinera; en rutas, paradas a lo largo del recorrido) y los botones Ir / Hecho / Guardar.

## Cómo añadir pins nuevos
1. Guarda la lista en `datos/recibidos-N.json` con el formato `{ "lugares": [ ... ] }` y ids que no existan.
2. `powershell -File tools\anadir-lugares.ps1 -Desde datos\recibidos-N.json` (valida campos obligatorios y no duplica ids).
3. Si hay rutas: `powershell -File tools\comprobar-rutas.ps1` → coloca los puertos en el nodo del puerto de OpenStreetMap y los pueblos en su centro, y guarda `km_ruta`. Revisa los avisos (medias vueltas, puntos lejos de la carretera).
4. `powershell -File tools\enriquecer.ps1` → busca el artículo de Wikipedia y los datos de Wikidata. Revisa `datos\informe-enriquecer.txt`; si un artículo es el equivocado, pon el título correcto en `wiki`, **borra `wikidata`** (si no, se reutiliza el viejo) y ejecuta `tools\enriquecer.ps1 -Ids N`.
5. Prueba en local y publica (`git push`): la tablet recibe los pins sola la próxima vez que abra la app con conexión.

Aunque no se ejecute el paso 4, la app busca sola el artículo de Wikipedia por cercanía y nombre (menos preciso).

## Viaje con varias paradas
- Desde la tarjeta, «Añadir al viaje». La pestaña **Viaje** lista las paradas (subir, bajar, quitar), calcula km y tiempo desde tu posición y dibuja el camino.
- Se guarda en `localStorage` dentro de `rutasMoto.v2`, como `plan` (lista de ids en orden).
- «Mejor orden»: vecino más cercano + 2-opt con distancias en línea recta, en el propio navegador (sin peticiones). Las rutas se tratan como un bloque con su sentido.
- Un lugar es un punto `break` (se puede dar la vuelta allí); una ruta aporta todo su `recorrido` como `break_through`.
- **Valhalla de FOSSGIS admite 10 puntos por petición** (salida + 9). El resumen se calcula por tramos encadenados; la navegación calcula 9 puntos y, al llegar al último, pide el siguiente tramo.
- Al llegar a cada parada: el lugar queda visitado; la ruta, hecha si se ha recorrido el 80 %.
- Ganchos de prueba: `__app.plan([ids])`, `__app.startTrip()`.

## Viaje improvisado («Improvisar», arriba en el panel)
- Pregunta Media tarde (3,5 h), Día completo (8 h) o Dos días (15 h, durmiendo fuera). Tiempos con paradas incluidas (20 min por lugar).
- Bucle al azar desde tu posición y **vuelta al punto de salida** (`S.planMeta.back`). En dos días, el punto más lejano es donde se duerme (mejor un pueblo bonito: `nightId`).
- **Los sitios hechos nunca entran solos**: solo se va a ellos a mano (desde su tarjeta).
- Se calibra con el servidor: primer intento con 30 km/h en línea recta, se pide el camino real una vez y se vuelve a elegir con la velocidad medida (Valhalla sin autovías da medias de ~27 km/h en sierra).
- Llena el mismo viaje (`S.plan`), así que se ve y se navega desde la pestaña Viaje. «Otro viaje» prepara otro igual. Al retomarlo se saltan las paradas hechas desde que se preparó.

## Casa y Trabajo
- Botón «Casa» arriba en el panel. Direcciones en `S.home` / `S.work` (solo en el aparato; buscadas con Nominatim o «Usar mi posición actual»).
- Ir a casa/trabajo usa `fast`: Valhalla con `use_highways` 1 (lo más directo, con autovía), sin importar el ajuste «Ir sin autovías».

## Sitios hechos
- En el mapa, el pin hecho es blanco con aro y un ✓ del color de su capa (dibujado en canvas, clase `Pin`); en las listas, un ✓ en lugar del punto.

## Roadbook (pantalla de maniobras)
- Se abre sola al pulsar Ir / Empezar ruta / Empezar viaje. La flecha de volver lleva al mapa (la navegación sigue); el botón «Roadbook» la reabre.
- Aquí el usuario pidió **fondo negro, tarjetas grafito y amarillo lima** (excepción al blanco del resto de la app).
- Cabecera: volver, estado (km y llegada, o «Recalculando…») y círculo de límite (rojo con número blanco si la velocidad GPS lo supera; «—» sin dato).
- Tarjeta principal (~80 %): dibujo del cruce, distancia e instrucción. Tarjeta inferior (~20 %): «Después · 100 m — Gira a la izquierda».
- Datos: maniobras de Valhalla + `trace_attributes` de la ruta (POST con `text/plain` para evitar la petición previa de CORS), por tramos de ≤2500 puntos/80 km, uno tras otro. De ahí salen ramales del cruce, calles intermedias («Toma la segunda a la derecha»), glorietas y límite.
- Glorietas: al acercarse (≤2 km) se pide el resto del anillo (ruta de la salida a la entrada + `trace_attributes`) para dibujar todas las salidas.
- Aviso: tres pulsos del borde (100 ms encendido, 90 ms pausa; 480 ms), una vez por maniobra. Autovía/salidas: a 200 m. Resto: lo que se recorre en 5 s (mín. 25 m), y solo cuando ya no quedan calles intermedias.
- La tarjeta cambia cuando la posición sobre la ruta pasa 15 m del punto de maniobra (en glorietas, del punto de salida).
- Con OSRM (reserva) no hay límite ni calles intermedias; los cruces salen de sus `intersections`.
- Ganchos de prueba: `__app.rb.state.log` (avisos dados), `__app.rb.state.swaps`.

## Servicios externos (sin clave)
- Mapa: Esri World Topo Map (`server.arcgisonline.com`, sin clave, en color y con nombres). CARTO Voyager ya pide clave: no usarlo.
- Rutas: Valhalla de FOSSGIS (`valhalla1.openstreetmap.de`, modo `motorcycle`, `use_highways` 0 = sin autovías); OSRM público de reserva.
- Servicios cercanos: Overpass (3 servidores en cadena; a veces saturados, la tarjeta oculta la sección si fallan).
- Wikipedia REST (resumen y foto) y Wikidata (datos). Wikimedia solo sirve miniaturas de tamaños estándar (330, 500, 960 px…).
- Herramientas: Nominatim (máx. 1 petición/s) y OSRM `nearest`.

## Pendiente
- Lugares 312–520 de la lista del usuario: el mensaje llegó cortado en el 312. Cuando los envíe, seguir "Cómo añadir pins nuevos".
- Vuelta por un camino distinto en viajes hechos a mano (el improvisado ya es un bucle). Se podría evitar el trazado de ida.
