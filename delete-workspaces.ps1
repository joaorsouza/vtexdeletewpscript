<#
.SYNOPSIS
  Apaga workspaces VTEX em lote na conta logada.

.EXAMPLE
  # dry-run: só mostra o que seria apagado
  .\delete-workspaces.ps1 -Pattern '^(kamity|kstaging|novaarq)\d*$'

  # apaga de verdade
  .\delete-workspaces.ps1 -Pattern '^(kamity|kstaging|novaarq)\d*$' -Apply

  # lista explícita em arquivo (um nome por linha)
  .\delete-workspaces.ps1 -FromFile .\apagar.txt -Apply

  # modo inverso: apaga TUDO exceto os nomes do arquivo (master, atual e production continuam protegidos)
  .\delete-workspaces.ps1 -KeepFile .\manter.txt
#>
param(
  [string]$Pattern,            # regex aplicada ao nome do workspace
  [string]$FromFile,           # arquivo com um nome por linha
  [string[]]$Names,            # nomes passados direto
  [string]$KeepFile,           # modo inverso: apaga tudo que NÃO está neste arquivo
  [switch]$IncludeProduction,  # por padrão workspaces production=true são ignorados
  [switch]$Apply,              # sem isso é dry-run
  [int]$BatchSize = 10
)

$ErrorActionPreference = 'Stop'
$protected = @('master')

# --- lista atual da conta
$raw = vtex workspace list 2>&1 | Out-String
# o workspace em uso vem marcado com "* " na frente do nome
$rows = $raw -split "`r?`n" | Where-Object { $_ -match '^\s*(\*\s+)?(\S+)\s+(\d+)\s+(true|false)\s*$' } |
  ForEach-Object {
    [pscustomobject]@{ Name = $Matches[2]; Weight = [int]$Matches[3]; Production = ($Matches[4] -eq 'true'); Current = [bool]$Matches[1] }
  }
if (-not $rows) { throw "Não consegui ler a lista de workspaces. Saída:`n$raw" }

$current = ($rows | Where-Object Current | Select-Object -First 1).Name

# --- seleção
$wanted = @()
if ($Pattern)  { $wanted += ($rows | Where-Object { $_.Name -match $Pattern }).Name }
if ($FromFile) { $wanted += Get-Content $FromFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } }
if ($Names)    { $wanted += $Names }
if ($KeepFile) {
  $keep = Get-Content $KeepFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
  $missing = $keep | Where-Object { $_ -notin $rows.Name }
  if ($missing) { Write-Host "Aviso: nomes do KeepFile que não existem na conta: $($missing -join ', ')" -ForegroundColor DarkYellow }
  $wanted += ($rows | Where-Object { $_.Name -notin $keep }).Name
}
$wanted = $wanted | Sort-Object -Unique
if (-not $wanted) { throw 'Nenhum critério informado (-Pattern, -FromFile, -Names ou -KeepFile).' }

$existing = @{}; $rows | ForEach-Object { $existing[$_.Name] = $_ }

$toDelete = @(); $skipped = @()
foreach ($n in $wanted) {
  if ($protected -contains $n)              { $skipped += "$n (protegido)"; continue }
  if ($n -eq $current)                      { $skipped += "$n (workspace atual, troque antes)"; continue }
  if (-not $existing.ContainsKey($n))       { $skipped += "$n (não existe)"; continue }
  if ($existing[$n].Production -and -not $IncludeProduction) { $skipped += "$n (production=true; use -IncludeProduction)"; continue }
  $toDelete += $n
}

Write-Host "`nSerão apagados ($($toDelete.Count)):" -ForegroundColor Yellow
$toDelete | ForEach-Object { "  $_" }
if ($skipped) { Write-Host "`nIgnorados ($($skipped.Count)):" -ForegroundColor DarkGray; $skipped | ForEach-Object { "  $_" } }

if (-not $Apply) { Write-Host "`nDRY-RUN. Rode de novo com -Apply para executar." -ForegroundColor Cyan; exit 0 }
if (-not $toDelete) { exit 0 }

# --- execução em lotes
$ok = @(); $fail = @()
for ($i = 0; $i -lt $toDelete.Count; $i += $BatchSize) {
  $batch = $toDelete[$i..([Math]::Min($i + $BatchSize, $toDelete.Count) - 1)]
  Write-Host "`n> vtex workspace delete -y $($batch -join ' ')" -ForegroundColor Cyan
  $out = & vtex workspace delete -y @batch 2>&1 | Out-String
  Write-Host $out
  if ($LASTEXITCODE -eq 0) { $ok += $batch } else { $fail += $batch }
}

Write-Host "`nApagados: $($ok.Count)  Falharam: $($fail.Count)" -ForegroundColor Green
if ($fail) { $fail | ForEach-Object { "  FALHOU: $_" } }
