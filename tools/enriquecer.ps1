<#
  Investiga cada lugar en Wikidata y Wikipedia (español) y completa lugares.json con:
    wiki              título del artículo en es.wikipedia ("" = buscado y no encontrado).
                      La app lo usa para mostrar foto y resumen.
    wikidata          identificador Q...
    habitantes        población (y habitantes_anio)
    altitud_m         solo si no venía en los datos
    epoca             siglo o año de origen/construcción, p. ej. "s. XIII" o "1221"
    estilo            estilo artístico (monumentos e historia)
    proteccion        figura de protección más importante (y proteccion_anio)
    superficie_km2    extensión (paisajes naturales)
  Corrige lat/lon con las coordenadas de Wikidata cuando están cerca (pueblos y monumentos: 15 km; rutas: 3 km;
  paisajes: nunca, porque el punto suele ser un sitio de visita elegido a propósito).

  Usa el servicio de consultas de Wikidata (query.wikidata.org): pocas consultas grandes en vez de cientos de
  peticiones sueltas, que la API de Wikipedia corta por exceso de uso.

  Por defecto solo procesa los lugares aún no investigados (sin "wikidata" y sin "wiki").
    -Ids 12,40     procesa solo esos ids (si ya tienen "wiki" o "wikidata", se usan tal cual: sirve para corregir a mano)
    -Buscar        con -Ids, vuelve a buscar aunque ya tengan "wiki"
  El informe queda en datos\informe-enriquecer.txt
#>
param([int[]]$Ids, [switch]$Buscar)
. (Join-Path $PSScriptRoot 'comun.ps1')

$inv = [Globalization.CultureInfo]::InvariantCulture
$tmp = Join-Path $env:TEMP 'rutas-sparql'; New-Item -ItemType Directory -Force $tmp | Out-Null
$STOP = @('de', 'del', 'la', 'las', 'el', 'los', 'y', 'e', 'i', 'en', 'a', 'd', 'l', 'les', 'dels', 'sa', 'es', 's', 'o', 'da', 'do', 'das', 'dos', 'al', 'lo', 'ses', 'na')

# ---------- consulta SPARQL (curl.exe para no tener problemas de codificación) ----------
function Invoke-Sparql([string]$Query) {
  $qf = Join-Path $tmp 'q.rq'; $of = Join-Path $tmp 'r.csv'
  [IO.File]::WriteAllText($qf, $Query, (New-Object Text.UTF8Encoding($false)))
  for ($i = 0; $i -lt 3; $i++) {
    if (Test-Path $of) { Remove-Item $of -Force }
    $code = & curl.exe -s -A $script:UA -H 'Accept: text/csv' --data-urlencode "query@$qf" -o $of -w '%{http_code}' --max-time 90 'https://query.wikidata.org/sparql'
    if ($code -eq '200' -and (Test-Path $of)) { return @(Get-Content $of -Encoding UTF8 | ConvertFrom-Csv) }
    Start-Sleep -Seconds (10 * ($i + 1))
  }
  Write-Output "  (una consulta falló 3 veces; esos lugares quedan sin investigar)" | Out-Host
  return $null
}
function Get-Q([string]$uri) { return ($uri -replace '^.*/entity/', '') }
function Get-Titulo([string]$url) { if (-not $url) { return '' }; return [uri]::UnescapeDataString(($url -replace '^https://es\.wikipedia\.org/wiki/', '')).Replace('_', ' ') }
function Get-Coord([string]$wkt) { $m = [regex]::Match($wkt, 'Point\(([-\d.eE]+) ([-\d.eE]+)\)'); if ($m.Success) { return @([double]::Parse($m.Groups[2].Value, $inv), [double]::Parse($m.Groups[1].Value, $inv)) }; return $null }
function Q([string]$s) { return '"' + $s.Replace('\', '\\').Replace('"', '\"') + '"' }

# ---------- parecido de nombres ----------
function Get-Tokens([string]$s) { return @((ConvertTo-Normal $s).Split(' ') | Where-Object { $_ -and ($STOP -notcontains $_) }) }
function Get-Score([string]$nombre, [string]$titulo) {
  $tn = @(Get-Tokens $nombre); $tt = @(Get-Tokens $titulo)
  if ($tn.Count -eq 0 -or $tt.Count -eq 0) { return 0 }
  $comun = @($tn | Where-Object { $tt -contains $_ } | Select-Object -Unique).Count
  if ($comun -eq 0) { return 0 }
  $c1 = $comun / $tn.Count; $c2 = $comun / $tt.Count
  $s = 0.7 * [Math]::Max($c1, $c2) + 0.3 * [Math]::Min($c1, $c2)
  $base = $titulo -replace '\s*\([^)]*\)\s*$', ''
  if ((ConvertTo-Normal $base) -eq (ConvertTo-Normal $nombre)) { $s += 0.5 }
  if ($tn[0] -eq $tt[0]) { $s += 0.1 }
  return $s
}
# Artículos que suelen colarse por llamarse igual o estar cerca: estaciones, barrios, clubes...
function Get-Penalizacion([string]$nombre, [string]$texto) {
  $tn = @(Get-Tokens $nombre); $tt = @(Get-Tokens $texto); $p = 0
  foreach ($w in 'estacion', 'apeadero', 'anexo', 'batalla', 'club', 'aeropuerto', 'linea', 'hotel', 'colegio', 'instituto', 'parroquia', 'diocesis', 'elecciones', 'barrio', 'distrito', 'metro', 'calle', 'plaza') {
    if ($tt -contains $w -and $tn -notcontains $w) { $p = 1.0 }
  }
  return $p
}
function Get-Nombres($l) {
  $n = (($l.nombre -replace '^Pto\.\s*', 'Puerto ') -replace '\s+', ' ').Trim()
  $alt = @()
  $m = [regex]::Match($n, '\(([^)]+)\)'); if ($m.Success) { $alt += $m.Groups[1].Value.Trim() }
  foreach ($sep in @(',', ':', '(', ' – ', ' - ', ' y ')) { $i = $n.IndexOf($sep); if ($i -gt 2) { $alt += $n.Substring(0, $i).Trim() } }
  return @{ principal = $n; alternativos = @($alt | Where-Object { $_ -and $_ -ne $n } | Select-Object -Unique) }
}

# ---------- 1. buscar candidatos por nombre ----------
function Find-Candidatos([string[]]$nombres) {
  $res = @{}
  for ($i = 0; $i -lt $nombres.Count; $i += 12) {
    $lote = $nombres[$i..([Math]::Min($i + 12, $nombres.Count) - 1)]
    $q = 'SELECT ?name ?item ?label ?coord ?article WHERE { VALUES ?name { ' + (($lote | ForEach-Object { Q $_ }) -join ' ') + ' }
      SERVICE wikibase:mwapi { bd:serviceParam wikibase:endpoint "www.wikidata.org" ; wikibase:api "EntitySearch" ; mwapi:search ?name ; mwapi:language "es" ; mwapi:limit "25" .
        ?item wikibase:apiOutputItem mwapi:item . }
      OPTIONAL { ?item wdt:P625 ?coord }
      OPTIONAL { ?item rdfs:label ?label FILTER(LANG(?label) = "es") }
      OPTIONAL { ?article schema:about ?item ; schema:isPartOf <https://es.wikipedia.org/> . } }'
    $filas = Invoke-Sparql $q
    foreach ($f in @($filas)) {
      if (-not $f) { continue }
      if (-not $res.ContainsKey($f.name)) { $res[$f.name] = New-Object System.Collections.ArrayList }
      [void]$res[$f.name].Add([pscustomobject]@{ q = (Get-Q $f.item); label = $f.label; coord = (Get-Coord $f.coord); titulo = (Get-Titulo $f.article) })
    }
    Write-Output ("  búsqueda {0}/{1}" -f [Math]::Min($i + 12, $nombres.Count), $nombres.Count) | Out-Host
    Start-Sleep -Seconds 2
  }
  return $res
}

function Select-Mejor($l, $cands, [string]$alt = '') {
  $maxKm = $(switch ($l.capa) { 'paisajes_naturales' { 40 } 'carreteras_puertos' { 25 } default { 15 } })
  $mejor = $null; $mejorS = 0; $conArt = $null; $conArtS = 0
  foreach ($c in $cands) {
    if (-not $c.coord) { continue }
    $d = Get-DistKm ([double]$l.lat) ([double]$l.lon) $c.coord[0] $c.coord[1]
    if ($d -gt $maxKm) { continue }
    $s = 0
    foreach ($t in @($c.label, $c.titulo)) {
      if (-not $t) { continue }
      $s = [Math]::Max($s, (Get-Score $l.nombre $t))
      if ($alt) { $s = [Math]::Max($s, 0.95 * (Get-Score $alt $t)) }
    }
    $s -= [Math]::Max((Get-Penalizacion $l.nombre $c.label), (Get-Penalizacion $l.nombre $c.titulo))
    if ($c.titulo) { $s += 0.15 }          # mejor si tiene artículo en español (foto y resumen)
    $s -= 0.01 * $d
    if ($s -gt $mejorS) { $mejorS = $s; $mejor = $c }
    if ($c.titulo -and $s -gt $conArtS) { $conArtS = $s; $conArt = $c }
  }
  # si el mejor no tiene artículo pero hay otro bueno que sí, se prefiere el que lo tiene
  if ($mejor -and -not $mejor.titulo -and $conArt -and $conArtS -ge 0.75) { $mejor = $conArt; $mejorS = $conArtS }
  if ($mejorS -lt 0.6) { return $null }
  $mejor | Add-Member -NotePropertyName score -NotePropertyValue ([Math]::Round($mejorS, 2)) -Force
  return $mejor
}

# ---------- 2. datos de Wikidata (por propiedad, en lotes) ----------
function Get-Datos([string[]]$qs, [string]$patron) {
  $out = @()
  for ($i = 0; $i -lt $qs.Count; $i += 150) {
    $lote = $qs[$i..([Math]::Min($i + 150, $qs.Count) - 1)]
    $q = 'SELECT * WHERE { VALUES ?item { ' + (($lote | ForEach-Object { 'wd:' + $_ }) -join ' ') + ' } ' + $patron + ' }'
    $r = Invoke-Sparql $q; if ($r) { $out += $r }
    Start-Sleep -Seconds 2
  }
  return $out
}
function Convert-Romano([int]$n) {
  $v = @(1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1); $r = @('M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I'); $s = ''
  for ($i = 0; $i -lt $v.Count; $i++) { while ($n -ge $v[$i]) { $s += $r[$i]; $n -= $v[$i] } }
  return $s
}
function Get-AnioTexto([string]$t) { $m = [regex]::Match($t, '^(-?)0*(\d+)-'); if ($m.Success) { return @{ anio = [int]$m.Groups[2].Value; ac = ($m.Groups[1].Value -eq '-') } }; return $null }
function Format-Epoca([string]$t, [int]$prec) {
  $a = Get-AnioTexto $t; if (-not $a) { return $null }
  $suf = $(if ($a.ac) { ' a. C.' } else { '' })
  if ($prec -ge 9) { return "$($a.anio)$suf" }
  if ($prec -eq 8) { return "años $([int]([Math]::Floor($a.anio / 10) * 10))$suf" }
  if ($prec -eq 7) { return 's. ' + (Convert-Romano ([int][Math]::Floor(($a.anio - 1) / 100) + 1)) + $suf }
  return $null
}
function Format-Etiqueta([string]$s) { if (-not $s) { return $null }; return $s.Substring(0, 1).ToUpper() + $s.Substring(1) }

# ================= proceso =================
$datos = Read-Lugares
$todos = @($datos.lugares)
if ($Ids) { $lista = @($todos | Where-Object { $Ids -contains [int]$_.id }) }
else { $lista = @($todos | Where-Object { -not $_.wikidata -and ($null -eq $_.PSObject.Properties['wiki']) }) }
Write-Output "Lugares a investigar: $($lista.Count)"

$elegido = @{}   # id -> candidato
foreach ($l in $lista) { if ($l.wikidata -and -not $Buscar) { $elegido[[string]$l.id] = [pscustomobject]@{ q = $l.wikidata; titulo = $l.wiki; coord = $null; score = 9 } } }
# Corrección a mano: si un lugar tiene "wiki" pero no "wikidata", se busca el elemento de ese artículo.
$manual = @($lista | Where-Object { $_.wiki -and -not $_.wikidata -and -not $Buscar })
if ($manual.Count) {
  $q = 'SELECT ?t ?item WHERE { VALUES ?t { ' + (($manual | ForEach-Object { (Q $_.wiki) + '@es' }) -join ' ') + ' } ?a schema:name ?t ; schema:isPartOf <https://es.wikipedia.org/> ; schema:about ?item . }'
  $porT = @{}; foreach ($f in @(Invoke-Sparql $q)) { if ($f) { $porT[$f.t] = Get-Q $f.item } }
  foreach ($l in $manual) {
    if ($porT.ContainsKey($l.wiki)) { $elegido[[string]$l.id] = [pscustomobject]@{ q = $porT[$l.wiki]; titulo = $l.wiki; coord = $null; score = 9 } }
    else { Write-Output "  Aviso: no existe el artículo '$($l.wiki)' (id $($l.id))" }
  }
}
$pend = @($lista | Where-Object { -not $elegido.ContainsKey([string]$_.id) -and ($Buscar -or -not $_.wikidata) })
# los datos investigados se recalculan desde cero (la altitud no, porque puede venir del usuario)
foreach ($l in $lista) { foreach ($k in 'habitantes', 'habitantes_anio', 'epoca', 'estilo', 'proteccion', 'proteccion_anio', 'superficie_km2') { $l.PSObject.Properties.Remove($k) } }

foreach ($pasada in 1, 2) {
  $porNombre = @{}
  foreach ($l in $pend) {
    # en la 2ª pasada también se reintentan los que encontraron elemento pero sin artículo en español
    if ($elegido.ContainsKey([string]$l.id) -and ($pasada -eq 1 -or $elegido[[string]$l.id].titulo)) { continue }
    $ns = Get-Nombres $l
    $usar = $(if ($pasada -eq 1) { @($ns.principal) } else { $ns.alternativos })
    foreach ($n in $usar) { if (-not $porNombre.ContainsKey($n)) { $porNombre[$n] = @() }; $porNombre[$n] += $l }
  }
  if ($porNombre.Count -eq 0) { continue }
  Write-Output "Pasada $pasada · nombres a buscar: $($porNombre.Count)"
  $cands = Find-Candidatos @($porNombre.Keys)
  foreach ($n in $porNombre.Keys) {
    if (-not $cands.ContainsKey($n)) { continue }
    foreach ($l in $porNombre[$n]) {
      $ya = $elegido[[string]$l.id]
      if ($ya -and $ya.titulo) { continue }
      $m = Select-Mejor $l $cands[$n] $(if ($pasada -eq 2) { $n } else { '' })
      if ($m -and (-not $ya -or ($m.titulo -and $m.score -ge 0.75))) { $elegido[[string]$l.id] = $m }
    }
  }
}

# Último recurso para monumentos, paisajes e historia sin coincidencia: el artículo del pueblo donde están
# (solo para foto y resumen; no se toman datos ni coordenadas de él).
$respaldo = @{}
$sinNada = @($pend | Where-Object { -not $elegido.ContainsKey([string]$_.id) -and $_.capa -ne 'pueblos_bonitos' -and $_.lugar -and $_.lugar -ne $_.nombre })
if ($sinNada.Count) {
  $porLugar = @{}; foreach ($l in $sinNada) { $k = ($l.lugar -replace '\s*\(.*$', '').Trim(); if (-not $porLugar.ContainsKey($k)) { $porLugar[$k] = @() }; $porLugar[$k] += $l }
  Write-Output "Pasada 3 (pueblo del lugar) · nombres a buscar: $($porLugar.Count)"
  $cands = Find-Candidatos @($porLugar.Keys)
  foreach ($k in $porLugar.Keys) {
    if (-not $cands.ContainsKey($k)) { continue }
    foreach ($l in $porLugar[$k]) {
      $mejor = $null; $mejorS = 0
      foreach ($c in $cands[$k]) {
        if (-not $c.coord -or -not $c.titulo) { continue }
        $d = Get-DistKm ([double]$l.lat) ([double]$l.lon) $c.coord[0] $c.coord[1]; if ($d -gt 15) { continue }
        $s = (Get-Score $k $c.titulo) - (Get-Penalizacion $k $c.titulo) - 0.01 * $d
        if ($s -gt $mejorS) { $mejorS = $s; $mejor = $c }
      }
      if ($mejor -and $mejorS -ge 1.0) { $respaldo[[string]$l.id] = $mejor.titulo }
    }
  }
}

$qs = @($elegido.Values | ForEach-Object { $_.q } | Select-Object -Unique)
Write-Output "Con elemento de Wikidata: $($elegido.Count) de $($lista.Count). Descargando datos..."
$pob = Get-Datos $qs '?item p:P1082 ?st . ?st psv:P1082/wikibase:quantityAmount ?v ; wikibase:rank ?rank . OPTIONAL { ?st pq:P585 ?t }'
$alt = Get-Datos $qs '?item p:P2044/psv:P2044 ?n . ?n wikibase:quantityAmount ?v ; wikibase:quantityUnit ?u .'
$inc = Get-Datos $qs '?item p:P571/psv:P571 ?n . ?n wikibase:timeValue ?t ; wikibase:timePrecision ?p .'
$est = Get-Datos $qs '?item wdt:P149 ?s . ?s rdfs:label ?v FILTER(LANG(?v) = "es")'
$pro = Get-Datos $qs '?item p:P1435 ?st . ?st ps:P1435 ?h . ?h rdfs:label ?v FILTER(LANG(?v) = "es") OPTIONAL { ?st pq:P580 ?t }'
$sup = Get-Datos $qs '?item p:P2046/psv:P2046 ?n . ?n wikibase:quantityAmount ?v ; wikibase:quantityUnit ?u .'
$coo = Get-Datos $qs '?item wdt:P625 ?c .'
$art = Get-Datos $qs 'OPTIONAL { ?article schema:about ?item ; schema:isPartOf <https://es.wikipedia.org/> . }'
function Group-Q($filas) { $h = @{}; foreach ($f in @($filas)) { if (-not $f) { continue }; $k = Get-Q $f.item; if (-not $h.ContainsKey($k)) { $h[$k] = @() }; $h[$k] += $f }; return $h }
$G = @{ pob = (Group-Q $pob); alt = (Group-Q $alt); inc = (Group-Q $inc); est = (Group-Q $est); pro = (Group-Q $pro); sup = (Group-Q $sup); coo = (Group-Q $coo); art = (Group-Q $art) }

$informe = New-Object System.Collections.ArrayList
$movidos = 0
foreach ($l in $lista) {
  $c = $elegido[[string]$l.id]
  if (-not $c) {
    if ($respaldo[[string]$l.id]) {
      Set-Campo $l 'wiki' $respaldo[[string]$l.id]
      [void]$informe.Add(('{0,5}  {1,-46} -> {2}  [artículo del pueblo, sin datos]' -f $l.id, $l.nombre, $l.wiki)); continue
    }
    # sin "wiki": la app intentará encontrar el artículo sola por cercanía
    [void]$informe.Add(('{0,5}  {1,-46} -> (sin elemento en Wikidata)' -f $l.id, $l.nombre)); continue
  }
  $q = $c.q; $hechos = @()
  Set-Campo $l 'wikidata' $q
  $titulo = $(if ($G.art[$q] -and $G.art[$q][0].article) { Get-Titulo $G.art[$q][0].article } else { $c.titulo })
  if (-not $l.wiki -or $Buscar) { Set-Campo $l 'wiki' $(if ($titulo) { $titulo } else { '' }) }
  # habitantes (el preferido o el más reciente)
  if ($G.pob[$q] -and $l.capa -eq 'pueblos_bonitos') {
    $filas = @($G.pob[$q]); $pref = @($filas | Where-Object { $_.rank -match 'Preferred' })
    $cand = $(if ($pref.Count) { $pref } else { $filas })
    $m = $cand | Sort-Object { $a = Get-AnioTexto $_.t; if ($a) { $a.anio } else { 0 } } -Descending | Select-Object -First 1
    $n = [double]::Parse($m.v, $inv)
    if ($n -gt 0) { Set-Campo $l 'habitantes' ([int]$n); $a = Get-AnioTexto $m.t; if ($a) { Set-Campo $l 'habitantes_anio' $a.anio }; $hechos += "$([int]$n) hab." }
  }
  # altitud
  # altitud: pueblos y paisajes (en rutas, la del puerto la pone el usuario; en monumentos no aporta)
  if (-not $l.altitud_m -and $G.alt[$q] -and ($l.capa -eq 'pueblos_bonitos' -or $l.capa -eq 'paisajes_naturales')) {
    $f = @($G.alt[$q])[0]; $m = [double]::Parse($f.v, $inv); if ($f.u -match 'Q3710$') { $m = $m * 0.3048 }
    if ($m -gt 0 -and $f.u -match 'Q11573$|Q3710$') { Set-Campo $l 'altitud_m' ([int][Math]::Round($m)); $hechos += "$([int][Math]::Round($m)) m" }
  }
  # época
  if ($l.capa -ne 'pueblos_bonitos' -and $l.capa -ne 'carreteras_puertos' -and $G.inc[$q]) {
    $f = @($G.inc[$q] | Sort-Object { [int]$_.p } -Descending)[0]; $e = Format-Epoca $f.t ([int]$f.p)
    if ($e) { Set-Campo $l 'epoca' $e; $hechos += $e }
  }
  # estilo
  $estilos = @($G.est[$q] | Where-Object { $_ -and $_.v -notmatch '^Tipo ' })
  if (($l.capa -eq 'monumentos' -or $l.capa -eq 'historia') -and $estilos.Count) { $s = Format-Etiqueta $estilos[0].v; Set-Campo $l 'estilo' $s; $hechos += $s }
  # protección: Patrimonio de la Humanidad > Bien de Interés Cultural > otras
  if ($G.pro[$q]) {
    # se descartan registros genéricos que no dicen nada al usuario
    $filas = @($G.pro[$q] | Where-Object { $_.v -notmatch 'parte del patrimonio cultural|Tipo [A-Z]$' })
  }
  if ($G.pro[$q] -and $filas.Count) {
    $m = $filas | Sort-Object { $h = Get-Q $_.h; if ($h -eq 'Q9259') { 0 } elseif ($h -eq 'Q23712') { 1 } else { 5 } } | Select-Object -First 1
    $s = Format-Etiqueta $m.v; Set-Campo $l 'proteccion' $s
    $a = Get-AnioTexto $m.t; if ($a) { Set-Campo $l 'proteccion_anio' $a.anio }
    $hechos += $s
  }
  # superficie (paisajes)
  if ($l.capa -eq 'paisajes_naturales' -and $G.sup[$q]) {
    $f = @($G.sup[$q])[0]; $v = [double]::Parse($f.v, $inv); $km2 = $null
    if ($f.u -match 'Q712226$') { $km2 = $v } elseif ($f.u -match 'Q35852$') { $km2 = $v / 100 } elseif ($f.u -match 'Q25343$') { $km2 = $v / 1e6 }
    if ($km2 -gt 0) { Set-Campo $l 'superficie_km2' ([Math]::Round($km2, $(if ($km2 -lt 10) { 1 } else { 0 }))); $hechos += ('{0:0.#} km2' -f $km2) }
  }
  # coordenadas
  if ($G.coo[$q]) {
    $co = Get-Coord (@($G.coo[$q])[0].c)
    if ($co) {
      $d = Get-DistKm ([double]$l.lat) ([double]$l.lon) $co[0] $co[1]
      $max = $(switch ($l.capa) { 'paisajes_naturales' { 0 } 'carreteras_puertos' { 3 } default { 15 } })
      if ($d -gt 0.15 -and $d -lt $max) { $l.lat = [Math]::Round($co[0], 5); $l.lon = [Math]::Round($co[1], 5); $movidos++; $hechos += ('movido {0:0.0} km' -f $d) }
    }
  }
  [void]$informe.Add(('{0,5}  {1,-46} -> {2} ({3}) [{4}]  {5}' -f $l.id, $l.nombre, $l.wiki, $q, $c.score, ($hechos -join ' · ')))
}
Write-Lugares $datos
$rutaInf = Join-Path $script:Raiz 'datos\informe-enriquecer.txt'
[IO.File]::WriteAllLines($rutaInf, [string[]]$informe, (New-Object Text.UTF8Encoding($false)))
$conArt = @($lista | Where-Object { $_.wiki }).Count
Write-Output "Con artículo en Wikipedia: $conArt de $($lista.Count) · Coordenadas afinadas: $movidos · Informe: datos\informe-enriquecer.txt"
