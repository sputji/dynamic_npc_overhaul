# sync_to_mods.ps1
# Synchronise D:\PZ Mods\Dynamic_NPC_Overhaul\B42\ vers les dossiers mods PZ
# Usage : .\sync_to_mods.ps1

$src = "D:\PZ Mods\Dynamic_NPC_Overhaul\B42"
$destinations = @(
    "C:\Users\Nicolas\Zomboid\mods\PH_DynamicNPCOverhaul",
    "F:\Steam Games\steamapps\common\ProjectZomboid\mods\PH_DynamicNPCOverhaul"
)

foreach ($dest in $destinations) {
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    Copy-Item "$src\mod.info"    $dest -Force
    Copy-Item "$src\icon.png"    $dest -Force -ErrorAction SilentlyContinue
    Copy-Item "$src\preview.png" $dest -Force -ErrorAction SilentlyContinue
    Copy-Item "$src\42"          $dest -Recurse -Force
    Copy-Item "$src\common"      $dest -Recurse -Force
    Write-Host "[OK] Sync -> $dest"
}

Write-Host ""
Write-Host "Verification :"
Get-Content "C:\Users\Nicolas\Zomboid\mods\PH_DynamicNPCOverhaul\mod.info"
Write-Host ""
Write-Host "common/media/lua :"
Get-ChildItem "C:\Users\Nicolas\Zomboid\mods\PH_DynamicNPCOverhaul\common\media\lua" | Select-Object Name
