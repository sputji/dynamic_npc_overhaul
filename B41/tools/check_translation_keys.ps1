param(
    [string]$LocalizationLua = "media/lua/shared/NPCDialogueLocalization.lua",
    [string]$FrenchTxt = "media/lua/shared/Translate/FR/IG_UI_FR.txt",
    [string]$EnglishTxt = "media/lua/shared/Translate/EN/IG_UI_EN.txt",
    [switch]$FailOnDuplicate
)

$ErrorActionPreference = "Stop"

function Get-LuaKeys {
    param([string]$Path)
    $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $pattern = '^\s*(IGUI_[A-Z0-9_]+)\s*=\s*\{'
    Get-Content -LiteralPath $Path | ForEach-Object {
        if ($_ -match $pattern) {
            [void]$keys.Add($matches[1])
        }
    }
    return $keys
}

function Get-LuaEntries {
    param([string]$Path)
    $entries = @{}
    $pattern = '^\s*(IGUI_[A-Z0-9_]+)\s*=\s*\{\s*fr\s*=\s*"([^"]*)"\s*,\s*en\s*=\s*"([^"]*)"\s*\}'
    Get-Content -LiteralPath $Path | ForEach-Object {
        if ($_ -match $pattern) {
            $entries[$matches[1]] = @{
                fr = $matches[2]
                en = $matches[3]
            }
        }
    }
    return $entries
}

function Get-TxtKeys {
    param([string]$Path)
    $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $pattern = '^\s*(IGUI_[A-Z0-9_]+)\s*=\s*"'
    Get-Content -LiteralPath $Path | ForEach-Object {
        if ($_ -match $pattern) {
            [void]$keys.Add($matches[1])
        }
    }
    return $keys
}

function Get-TxtEntries {
    param([string]$Path)
    $entries = @{}
    $pattern = '^\s*(IGUI_[A-Z0-9_]+)\s*=\s*"([^"]*)"'
    Get-Content -LiteralPath $Path | ForEach-Object {
        if ($_ -match $pattern) {
            $entries[$matches[1]] = $matches[2]
        }
    }
    return $entries
}

function Find-EmptyValues {
    param([hashtable]$Entries)
    $keys = @()
    foreach ($k in $Entries.Keys) {
        $v = [string]$Entries[$k]
        if ([string]::IsNullOrWhiteSpace($v)) {
            $keys += $k
        }
    }
    return $keys | Sort-Object
}

function Normalize-TextForDuplicateCheck {
    param([string]$Text)
    $normalized = ($Text -replace '\s+', ' ').Trim().ToLowerInvariant()
    return $normalized
}

function Find-SuspiciousDuplicates {
    param([hashtable]$Entries)
    $groups = @{}
    foreach ($k in $Entries.Keys) {
        $v = [string]$Entries[$k]
        if ([string]::IsNullOrWhiteSpace($v)) {
            continue
        }
        $n = Normalize-TextForDuplicateCheck -Text $v
        if (-not $groups.ContainsKey($n)) {
            $groups[$n] = @()
        }
        $groups[$n] += $k
    }

    $duplicates = @()
    foreach ($n in $groups.Keys) {
        $keys = $groups[$n]
        if ($keys.Count -gt 1) {
            $duplicates += [pscustomobject]@{
                Text = $n
                Keys = ($keys | Sort-Object)
                Count = $keys.Count
            }
        }
    }

    return $duplicates | Sort-Object Count -Descending
}

function Compare-KeySets {
    param(
        [System.Collections.Generic.HashSet[string]]$Source,
        [System.Collections.Generic.HashSet[string]]$Target
    )

    $missing = @()
    foreach ($key in $Source) {
        if (-not $Target.Contains($key)) {
            $missing += $key
        }
    }
    return $missing | Sort-Object
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$luaPath = Join-Path $repoRoot $LocalizationLua
$frPath = Join-Path $repoRoot $FrenchTxt
$enPath = Join-Path $repoRoot $EnglishTxt

if (-not (Test-Path -LiteralPath $luaPath)) { throw "File not found: $luaPath" }
if (-not (Test-Path -LiteralPath $frPath)) { throw "File not found: $frPath" }
if (-not (Test-Path -LiteralPath $enPath)) { throw "File not found: $enPath" }

$luaKeys = Get-LuaKeys -Path $luaPath
$frKeys = Get-TxtKeys -Path $frPath
$enKeys = Get-TxtKeys -Path $enPath

$luaEntries = Get-LuaEntries -Path $luaPath
$frEntries = Get-TxtEntries -Path $frPath
$enEntries = Get-TxtEntries -Path $enPath

$missingInFr = Compare-KeySets -Source $luaKeys -Target $frKeys
$missingInEn = Compare-KeySets -Source $luaKeys -Target $enKeys
$extraInFr = Compare-KeySets -Source $frKeys -Target $luaKeys
$extraInEn = Compare-KeySets -Source $enKeys -Target $luaKeys

$luaFrValues = @{}
$luaEnValues = @{}
foreach ($k in $luaEntries.Keys) {
    $luaFrValues[$k] = [string]$luaEntries[$k].fr
    $luaEnValues[$k] = [string]$luaEntries[$k].en
}

$emptyLuaFr = Find-EmptyValues -Entries $luaFrValues
$emptyLuaEn = Find-EmptyValues -Entries $luaEnValues
$emptyFr = Find-EmptyValues -Entries $frEntries
$emptyEn = Find-EmptyValues -Entries $enEntries

$dupeLuaFr = Find-SuspiciousDuplicates -Entries $luaFrValues
$dupeLuaEn = Find-SuspiciousDuplicates -Entries $luaEnValues
$dupeFr = Find-SuspiciousDuplicates -Entries $frEntries
$dupeEn = Find-SuspiciousDuplicates -Entries $enEntries

Write-Host "=== PHNPC Translation Key Check (v1.0.1) ==="
Write-Host "Lua keys: $($luaKeys.Count)"
Write-Host "FR keys : $($frKeys.Count)"
Write-Host "EN keys : $($enKeys.Count)"
Write-Host ""

if (
    $missingInFr.Count -eq 0 -and $missingInEn.Count -eq 0 -and
    $extraInFr.Count -eq 0 -and $extraInEn.Count -eq 0 -and
    $emptyLuaFr.Count -eq 0 -and $emptyLuaEn.Count -eq 0 -and
    $emptyFr.Count -eq 0 -and $emptyEn.Count -eq 0 -and
    (($FailOnDuplicate -eq $false) -or (
        $dupeLuaFr.Count -eq 0 -and $dupeLuaEn.Count -eq 0 -and
        $dupeFr.Count -eq 0 -and $dupeEn.Count -eq 0
    ))
) {
    Write-Host "OK: Lua/FR/EN keysets are aligned."
    exit 0
}

if ($missingInFr.Count -gt 0) {
    Write-Host "Missing in FR:" -ForegroundColor Yellow
    $missingInFr | ForEach-Object { Write-Host "  - $_" }
}

if ($missingInEn.Count -gt 0) {
    Write-Host "Missing in EN:" -ForegroundColor Yellow
    $missingInEn | ForEach-Object { Write-Host "  - $_" }
}

if ($extraInFr.Count -gt 0) {
    Write-Host "Extra in FR (not in Lua table):" -ForegroundColor Cyan
    $extraInFr | ForEach-Object { Write-Host "  - $_" }
}

if ($extraInEn.Count -gt 0) {
    Write-Host "Extra in EN (not in Lua table):" -ForegroundColor Cyan
    $extraInEn | ForEach-Object { Write-Host "  - $_" }
}

if ($emptyLuaFr.Count -gt 0) {
    Write-Host "Empty values in Lua (fr):" -ForegroundColor Red
    $emptyLuaFr | ForEach-Object { Write-Host "  - $_" }
}

if ($emptyLuaEn.Count -gt 0) {
    Write-Host "Empty values in Lua (en):" -ForegroundColor Red
    $emptyLuaEn | ForEach-Object { Write-Host "  - $_" }
}

if ($emptyFr.Count -gt 0) {
    Write-Host "Empty values in FR txt:" -ForegroundColor Red
    $emptyFr | ForEach-Object { Write-Host "  - $_" }
}

if ($emptyEn.Count -gt 0) {
    Write-Host "Empty values in EN txt:" -ForegroundColor Red
    $emptyEn | ForEach-Object { Write-Host "  - $_" }
}

function Print-DupeSummary {
    param(
        [string]$Label,
        [array]$Dupes
    )
    if ($Dupes.Count -gt 0) {
        Write-Host "Suspicious duplicate texts in ${Label}:" -ForegroundColor Yellow
        foreach ($d in $Dupes) {
            $joinedKeys = ($d.Keys -join ", ")
            Write-Host "  - [$($d.Count)x] keys: $joinedKeys"
        }
    }
}

Print-DupeSummary -Label "Lua fr" -Dupes $dupeLuaFr
Print-DupeSummary -Label "Lua en" -Dupes $dupeLuaEn
Print-DupeSummary -Label "FR txt" -Dupes $dupeFr
Print-DupeSummary -Label "EN txt" -Dupes $dupeEn

$hasBlockingError = (
    $missingInFr.Count -gt 0 -or $missingInEn.Count -gt 0 -or
    $extraInFr.Count -gt 0 -or $extraInEn.Count -gt 0 -or
    $emptyLuaFr.Count -gt 0 -or $emptyLuaEn.Count -gt 0 -or
    $emptyFr.Count -gt 0 -or $emptyEn.Count -gt 0
)

if (-not $hasBlockingError -and $FailOnDuplicate) {
    $hasBlockingError = (
        $dupeLuaFr.Count -gt 0 -or $dupeLuaEn.Count -gt 0 -or
        $dupeFr.Count -gt 0 -or $dupeEn.Count -gt 0
    )
}

if (-not $hasBlockingError -and -not $FailOnDuplicate) {
    Write-Host "OK: Keysets aligned and no empty values. Duplicate report is informational." -ForegroundColor Green
    exit 0
}

exit 1
