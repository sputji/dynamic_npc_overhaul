param(
    [string]$ExamplesRoot = "mod example"
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$examplesPath = Join-Path $repoRoot $ExamplesRoot

if (-not (Test-Path -LiteralPath $examplesPath)) {
    throw "Dossier introuvable: $examplesPath"
}

Write-Host "=== Scan compatibilite B41/B42 - Mod Examples ==="
Write-Host "Root: $examplesPath"
Write-Host ""

$mods = Get-ChildItem -LiteralPath $examplesPath -Directory | Sort-Object Name
foreach ($mod in $mods) {
    $luaFiles = Get-ChildItem -LiteralPath $mod.FullName -Recurse -File -Filter *.lua -ErrorAction SilentlyContinue
    $b42Hits = @()

    foreach ($f in $luaFiles) {
        $text = Get-Content -LiteralPath $f.FullName -Raw
        if ($text -match "ZombiePrograms|ZombieClans|BanditUtils") {
            $rel = $f.FullName.Substring($repoRoot.Path.Length + 1)
            $b42Hits += $rel
        }
    }

    Write-Host "- Mod: $($mod.Name)"
    if ($b42Hits.Count -eq 0) {
        Write-Host "  Compat B41 probable: OUI"
    } else {
        Write-Host "  Compat B41 probable: PARTIELLE / NON (indices B42 detectes)"
        $b42Hits | Select-Object -First 8 | ForEach-Object { Write-Host "    * $_" }
        if ($b42Hits.Count -gt 8) {
            Write-Host "    * ... ($($b42Hits.Count - 8) autres)"
        }
    }
}

Write-Host ""
Write-Host "Conseil: importer les patterns UI/donnees, pas les APIs B42 directes."
