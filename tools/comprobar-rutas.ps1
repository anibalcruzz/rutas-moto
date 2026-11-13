<#
  Comprueba las rutas de lugares.json (los lugares que tienen "recorrido"):
  1. Cada punto del recorrido debe caer junto a una carretera (servicio "nearest" de OSRM).
     Si está a más de 300 m, lo busca por nombre en OpenStreetMap (Nominatim) y lo corrige
     cuando encuentra una posición mejor (puerto de montaña o pueblo a menos de 20 km).
  2. Calcula la ruta en modo moto sin autovías (Valhalla) y guarda los km reales en "km_ruta".
  Solo revisa las rutas sin "km_ruta", salvo que se use -Todo.
  Uso:  powershell -File tools\comprobar-rutas.ps1 [-Todo]
#>
param([switch]$Todo)
. (Join-Path $PSScriptRoot 'comun.ps1')

$inv = [Globalization.CultureInfo]::InvariantCulture
function F([double]$x) { return $x.ToString('0.#####', $inv) }

function Get-Snap([double]$lat, [double]$lon) {
  $j = Get-Json ('https://router.project-osrm.org/nearest/v1/driving/{0},{1}?number=1' -f (F $lon), (F $lat))
  if ($j -and $j.waypoints) { return [double]$j.waypoints[0].distance }
  return 99999
}

function Expand-Nombre([string]$n) {
  return (($n -replace '^Pto\.\s*', 'Puerto ') -replace '^Desf\.\s*', 'Desfiladero ')
}

function Find-Punto($p, [string]$comunidad) {
  $nombre = Expand-Nombre $p.nombre
  $esPaso = $nombre -match '^(Puerto|Port|Coll|Collada|Alto|Estacas)\b'
  $res = @()
  foreach ($q in @("$nombre, $comunidad, España", "$nombre, España")) {
    Start-Sleep -Milliseconds 1100   # Nominatim pide como máximo 1 petición por segundo
    $r = Get-Json ('https://nominatim.openstreetmap.org/search?format=json&limit=8&countrycodes=es&q=' + [uri]::EscapeDataString($q))
    if ($r) { $res = @($r); break }
  }
  $mejor = $null; $mejorClave = 1e9
  foreach ($c in $res) {
    $d = Get-DistKm ([double]$p.lat) ([double]$p.lon) ([double]::Parse($c.lat, $inv)) ([double]::Parse($c.lon, $inv))
    if ($d -gt 20) { continue }
    $prio = 3
    if ($c.class -eq 'mountain_pass' -or $c.type -eq 'mountain_pass') { $prio = $(if ($esPaso) { 0 } else { 2 }) }
    elseif ($c.class -eq 'place') { $prio = $(if ($esPaso) { 2 } else { 0 }) }
    elseif ($c.class -eq 'boundary') { $prio = 1 }
    $clave = $prio * 100 + $d
    if ($clave -lt $mejorClave) { $mejorClave = $clave; $mejor = $c }
  }
  return $mejor
}

function Get-RutaMoto($puntos) {
  $locs = @()
  for ($i = 0; $i -lt $puntos.Count; $i++) {
    $tipo = $(if ($i -eq 0 -or $i -eq $puntos.Count - 1) { 'break' } else { 'break_through' })
    $locs += @{ lat = [double]$puntos[$i].lat; lon = [double]$puntos[$i].lon; type = $tipo }
  }
  $body = @{ locations = $locs; costing = 'motorcycle'; costing_options = @{ motorcycle = @{ use_highways = 0; use_tolls = 0; use_trails = 0 } }; units = 'kilometers'; directions_type = 'maneuvers' } | ConvertTo-Json -Depth 6 -Compress
  Start-Sleep -Milliseconds 1100
  return Get-Json ('https://valhalla1.openstreetmap.de/route?json=' + [uri]::EscapeDataString($body))
}

$datos = Read-Lugares
$rutas = @($datos.lugares | Where-Object { $_.recorrido -and @($_.recorrido).Count -ge 2 -and ($Todo -or -not $_.km_ruta) })
Write-Output "Rutas a comprobar: $($rutas.Count)"
$corregidos = 0; $avisos = @()
foreach ($r in $rutas) {
  $pts = @($r.recorrido); $cambios = @()
  foreach ($p in $pts) {
    $s = Get-Snap ([double]$p.lat) ([double]$p.lon)
    $esPaso = (Expand-Nombre $p.nombre) -match '^(Puerto|Port|Coll|Collada|Alto|Estacas)\b'
    # Un punto cercano a una carretera puede estar en la carretera equivocada (pistas, accesos a estaciones de esquí...).
    # Por eso los puertos se colocan siempre en el nodo del puerto de OpenStreetMap, y los pueblos en su centro si el punto se aleja.
    if (-not $esPaso -and $s -le 150) { continue }
    $c = Find-Punto $p $r.comunidad
    if ($c) {
      $nlat = [Math]::Round([double]::Parse($c.lat, $inv), 5); $nlon = [Math]::Round([double]::Parse($c.lon, $inv), 5)
      $dmov = Get-DistKm ([double]$p.lat) ([double]$p.lon) $nlat $nlon
      $esNodoPaso = ($c.class -eq 'mountain_pass' -or $c.type -eq 'mountain_pass')
      if ($esPaso -and -not $esNodoPaso) { $c = $null }
      elseif ($dmov -gt $(if ($esPaso) { 8 } else { 5 })) { $c = $null }
    }
    if ($c) {
      $s2 = Get-Snap $nlat $nlon
      if ($s2 -lt 150 -and ($esPaso -or $s2 -lt $s)) {
        if ($dmov -gt 0.02) { $cambios += ('{0}: {1:0.0} km ({2})' -f $p.nombre, $dmov, $c.class); $p.lat = $nlat; $p.lon = $nlon; $corregidos++ }
        continue
      }
    }
    if ($s -gt 300) { $avisos += ('[{0}] {1}: punto a {2:0} m de la carretera, sin corrección' -f $r.id, $p.nombre, $s) }
  }
  $v = Get-RutaMoto $pts
  if ($v -and $v.trip) {
    $km = [Math]::Round([double]$v.trip.summary.length)
    $vueltas = @($v.trip.legs | ForEach-Object { $_.maneuvers } | Where-Object { $_.type -eq 12 -or $_.type -eq 13 }).Count
    Set-Campo $r 'km_ruta' ([int]$km)
    $extra = $(if ($vueltas) { " · $vueltas media(s) vuelta(s)" } else { '' })
    Write-Output ('[{0}] {1}: {2} km (aprox. {3}){4}{5}' -f $r.id, $r.nombre, $km, $r.km_aprox, $extra, $(if ($cambios) { ' · corregido: ' + ($cambios -join '; ') } else { '' }))
    if ($vueltas) { $avisos += "[$($r.id)] $($r.nombre): $vueltas media(s) vuelta(s) en el recorrido" }
  } else {
    $avisos += "[$($r.id)] $($r.nombre): no se pudo calcular la ruta en moto"
    Write-Output "[$($r.id)] $($r.nombre): SIN RUTA"
  }
}
Write-Lugares $datos
Write-Output "Puntos corregidos: $corregidos"
if ($avisos) { Write-Output '--- Avisos ---'; $avisos | ForEach-Object { Write-Output $_ } }
