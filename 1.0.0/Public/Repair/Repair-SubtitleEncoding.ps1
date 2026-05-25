function Repair-SubtitleEncoding {
    <#
    .SYNOPSIS
        Detects the current encoding of a subtitle file and re-saves it as UTF-8 without BOM.
    .DESCRIPTION
        Handles UTF-16 LE/BE, Windows-1252, ISO-8859-1, and UTF-8 with BOM.
        Reads the source file, re-encodes to UTF-8, and writes to the output path.
    .PARAMETER Path
        Path to the subtitle file to fix.
    .PARAMETER OutputPath
        Destination path. Defaults to overwriting the source file (use -WhatIf to preview).
    .EXAMPLE
        Repair-SubtitleEncoding -Path 'broken_encoding.srt'
    .EXAMPLE
        Repair-SubtitleEncoding -Path 'broken.srt' -OutputPath 'fixed.srt'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [string] $OutputPath
    )

    $resolvedPath = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
    $encodingInfo = Get-FileEncoding -Path $resolvedPath

    if ($encodingInfo.Name -eq 'UTF-8' -and -not $encodingInfo.HasBom) {
        Write-SubtitleLog -Message "'$resolvedPath' is already UTF-8 without BOM. No change needed." -Level Info
        return
    }

    Write-SubtitleLog -Message "Re-encoding '$resolvedPath' from $($encodingInfo.Name) to UTF-8." -Level Info

    $bytes   = [System.IO.File]::ReadAllBytes($resolvedPath)
    $content = $encodingInfo.Encoding.GetString($bytes)

    # Strip BOM character if present
    $content = Remove-ByteOrderMark -Text $content

    $dest    = if ($OutputPath) { $OutputPath } else { $resolvedPath }

    if ($PSCmdlet.ShouldProcess($dest, 'Re-encode to UTF-8')) {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($dest, $content, $utf8NoBom)
        Write-SubtitleLog -Message "Re-encoded to '$dest'." -Level Info
    }
}
