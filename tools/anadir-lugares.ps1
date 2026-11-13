<#
  Añade a lugares.json los lugares de un archivo recibido (mismo formato: { "lugares": [ ... ] }).
  - Solo añade los ids que no existen todavía; avisa de los repetidos.
  - Después ejecuta comprobar-rutas.ps1 y enriquecer.ps1 para investigar los nuevos.
  Uso:  powershell -File tools\anadir-lugares.ps1 -Desde datos\recibidos-2.json
#>
param([Parameter(Mandatory)][string]$Desde)
. (Join-Path $PSScriptRoot 'comun.ps1')

$nuevos = Read-Lugares (Resolve-Path $Desde).Path
if (Test-Path $script:ArchivoLugares) { $datos = Read-Lugares } else { $datos = [pscustomobject]@{ lugares = @() } }
$ids = @{}; foreach ($l in $datos.lugares) { $ids[[string]$l.id] = $true }
$lista = New-Object System.Collections.ArrayList; foreach ($l in $datos.lugares) { [void]$lista.Add($l) }
$ok = 0; $rep = 0
foreach ($l in $nuevos.lugares) {
  if ($ids.ContainsKey([string]$l.id)) { $rep++; Write-Output "Ya existe el id $($l.id) ($($l.nombre)): no se añade"; continue }
  foreach ($c in 'id', 'capa', 'nombre', 'lat', 'lon') { if ($null -eq $l.$c -or "$($l.$c)" -eq '') { throw "Al lugar '$($l.nombre)' (id $($l.id)) le falta el campo obligatorio '$c'" } }
  [void]$lista.Add($l); $ids[[string]$l.id] = $true; $ok++
}
$datos = [pscustomobject]@{ lugares = $lista.ToArray() }
Write-Lugares $datos
Write-Output "Añadidos: $ok · Repetidos: $rep · Total: $($lista.Count)"
