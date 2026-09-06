function Get-FileEncoding {
    <#
    .SYNOPSIS
        Detects the encoding of a file by inspecting BOM bytes and content heuristics.
    .OUTPUTS
        A hashtable with keys: Name (string), HasBom (bool), Encoding (System.Text.Encoding)
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)

    # BOM detection
    if ($bytes.Count -ge 4 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00) {
        return @{ Name = 'UTF-32LE'; HasBom = $true; Encoding = [System.Text.Encoding]::UTF32 }
    }
    if ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return @{ Name = 'UTF-8-BOM'; HasBom = $true; Encoding = [System.Text.Encoding]::UTF8 }
    }
    if ($bytes.Count -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return @{ Name = 'UTF-16LE'; HasBom = $true; Encoding = [System.Text.Encoding]::Unicode }
    }
    if ($bytes.Count -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return @{ Name = 'UTF-16BE'; HasBom = $true; Encoding = [System.Text.Encoding]::BigEndianUnicode }
    }

    # No BOM — try UTF-8 decode (check for replacement character U+FFFD)
    $utf8  = [System.Text.Encoding]::UTF8
    $text  = $utf8.GetString($bytes)
    if ($text -notmatch '\uFFFD') {
        return @{ Name = 'UTF-8'; HasBom = $false; Encoding = $utf8 }
    }

    # Fallback: Windows-1252 (most common legacy Western subtitle encoding)
    try {
        $win1252 = [System.Text.Encoding]::GetEncoding(1252)
        return @{ Name = 'Windows-1252'; HasBom = $false; Encoding = $win1252 }
    } catch {
        # If Windows-1252 unavailable (non-Windows), fall back to Latin-1
        $latin1 = [System.Text.Encoding]::GetEncoding('iso-8859-1')
        return @{ Name = 'ISO-8859-1'; HasBom = $false; Encoding = $latin1 }
    }
}
