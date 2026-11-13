# Funciones comunes de las herramientas de datos (PowerShell 5.1+).
$ErrorActionPreference = 'Stop'
$script:UA = 'rutas-moto-app/1.0'
$script:Raiz = Split-Path -Parent $PSScriptRoot
$script:ArchivoLugares = Join-Path $script:Raiz 'lugares.json'

function Get-Json([string]$Url, [int]$Intentos = 3) {
  for ($i = 0; $i -lt $Intentos; $i++) {
    try { return Invoke-RestMethod -Uri $Url -UserAgent $script:UA -TimeoutSec 40 }
    catch { Start-Sleep -Seconds (2 * ($i + 1)) }
  }
  return $null
}

function Read-Lugares([string]$Ruta = $script:ArchivoLugares) {
  $txt = [IO.File]::ReadAllText($Ruta, [Text.Encoding]::UTF8)
  return ($txt | ConvertFrom-Json)
}

# Escribe un objeto por línea para que el archivo sea fácil de leer y de editar a mano.
function Write-Lugares($Datos, [string]$Ruta = $script:ArchivoLugares) {
  $lineas = foreach ($l in ($Datos.lugares | Sort-Object { [int]$_.id })) {
    '    ' + ($l | ConvertTo-Json -Compress -Depth 8)
  }
  $cab = [ordered]@{ version = 2; actualizado = (Get-Date -Format 'yyyy-MM-dd'); total = @($Datos.lugares).Count }
  $txt = "{`n  `"version`": $($cab.version),`n  `"actualizado`": `"$($cab.actualizado)`",`n  `"total`": $($cab.total),`n  `"lugares`": [`n" + ($lineas -join ",`n") + "`n  ]`n}`n"
  # PowerShell 5.1 escapa algunos caracteres válidos; se dejan legibles.
  $bs = [string][char]92
  foreach ($par in @(@('0027', "'"), @('0026', '&'), @('003c', '<'), @('003e', '>'))) { $txt = $txt.Replace($bs + 'u' + $par[0], $par[1]) }
  [IO.File]::WriteAllText($Ruta, $txt, (New-Object Text.UTF8Encoding($false)))
}

function Set-Campo($Obj, [string]$Nombre, $Valor) {
  $Obj | Add-Member -NotePropertyName $Nombre -NotePropertyValue $Valor -Force
}

function Get-DistKm([double]$a, [double]$b, [double]$c, [double]$d) {
  $r = [Math]::PI / 180; $x = ($c - $a) * $r; $y = ($d - $b) * $r
  $h = [Math]::Sin($x / 2) * [Math]::Sin($x / 2) + [Math]::Cos($a * $r) * [Math]::Cos($c * $r) * [Math]::Sin($y / 2) * [Math]::Sin($y / 2)
  return 2 * 6371 * [Math]::Asin([Math]::Sqrt($h))
}

function ConvertTo-Normal([string]$s) {
  if (-not $s) { return '' }
  $d = $s.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object Text.StringBuilder
  foreach ($ch in $d.ToCharArray()) {
    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
  }
  return ((($sb.ToString() -replace '[^a-z0-9]+', ' ').Trim()) -replace '\bpto\b', 'puerto')
}
