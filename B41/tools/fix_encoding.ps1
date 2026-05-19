# fix_encoding.ps1
# Converts all non-ASCII chars in Lua files to pure ASCII for Kahlua (PZ Build 41) compatibility
# Removes UTF-8 BOM, replaces French accented chars, typographic punctuation, etc.

$modDir = "D:\PZ Mods\Dynamic_NPC_Overhaul\media\lua"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$enc = [System.Text.Encoding]::UTF8

$files = Get-ChildItem $modDir -Recurse -Filter "*.lua" | Where-Object {
    $b = [System.IO.File]::ReadAllBytes($_.FullName)
    ($b | Where-Object { $_ -gt 127 }).Count -gt 0
}

Write-Host "Files to fix: $($files.Count)"

foreach ($f in $files) {
    $text = [System.IO.File]::ReadAllText($f.FullName, $enc)

    # French/Latin accented characters -> ASCII equivalents
    $text = $text.Replace([char]0xe9, 'e').Replace([char]0xe8, 'e').Replace([char]0xea, 'e').Replace([char]0xeb, 'e')
    $text = $text.Replace([char]0xc9, 'E').Replace([char]0xc8, 'E').Replace([char]0xca, 'E')
    $text = $text.Replace([char]0xe0, 'a').Replace([char]0xe2, 'a').Replace([char]0xe4, 'a')
    $text = $text.Replace([char]0xc0, 'A').Replace([char]0xc2, 'A')
    $text = $text.Replace([char]0xee, 'i').Replace([char]0xef, 'i').Replace([char]0xce, 'I')
    $text = $text.Replace([char]0xf4, 'o').Replace([char]0xf6, 'o').Replace([char]0xd4, 'O')
    $text = $text.Replace([char]0xf9, 'u').Replace([char]0xfb, 'u').Replace([char]0xfc, 'u')
    $text = $text.Replace([char]0xd9, 'U').Replace([char]0xdb, 'U').Replace([char]0xdc, 'U')
    $text = $text.Replace([char]0xe7, 'c').Replace([char]0xc7, 'C')
    # Typographic dashes
    $text = $text.Replace([char]0x2013, '-').Replace([char]0x2014, '-')
    # Typographic quotes
    $text = $text.Replace([char]0x2018, "'").Replace([char]0x2019, "'")
    $text = $text.Replace([char]0x201c, '"').Replace([char]0x201d, '"')
    # Other
    $text = $text.Replace([char]0x2026, '...').Replace([char]0x2022, '-')
    $text = $text.Replace([char]0x00a0, ' ')
    # UTF-8 BOM character (U+FEFF)
    $text = $text.Replace([char]0xfeff, '')

    # Replace any remaining non-ASCII with '?'
    $cleaned = [System.Text.RegularExpressions.Regex]::Replace($text, '[^\x00-\x7F]', '?')

    [System.IO.File]::WriteAllText($f.FullName, $cleaned, $utf8NoBom)

    $rem = ([System.IO.File]::ReadAllBytes($f.FullName) | Where-Object { $_ -gt 127 }).Count
    Write-Host "$($f.Name): done (remaining non-ASCII: $rem)"
}

Write-Host "`nAll files converted to pure ASCII (no BOM)."
