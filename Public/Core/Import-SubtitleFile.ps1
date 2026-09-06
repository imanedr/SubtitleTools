function Import-SubtitleFile {
    <#
    .SYNOPSIS
        Reads a subtitle file from disk and returns a SubtitleFile object.
    .DESCRIPTION
        Auto-detects the format (SRT or ASS/SSA) from the file extension or content.
        Handles encoding detection automatically (UTF-8, UTF-8-BOM, UTF-16 LE/BE, Windows-1252).
    .PARAMETER Path
        Path to the subtitle file (.srt, .ass, or .ssa).
    .EXAMPLE
        $sub = Import-SubtitleFile -Path 'movie.srt'
    .EXAMPLE
        $sub = Import-SubtitleFile -Path 'anime.ass'
    #>
    [CmdletBinding()]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string] $Path
    )

    process {
        $resolvedPath = Resolve-Path -Path $Path -ErrorAction Stop | Select-Object -ExpandProperty Path

        # Detect encoding and read raw bytes
        $encodingInfo = Get-FileEncoding -Path $resolvedPath
        $rawBytes     = [System.IO.File]::ReadAllBytes($resolvedPath)
        $content      = $encodingInfo.Encoding.GetString($rawBytes)

        # Determine format from extension, fall back to content sniffing
        $ext    = [System.IO.Path]::GetExtension($resolvedPath).ToLower()
        $format = switch ($ext) {
            '.srt' { 'SRT' }
            '.ass' { 'ASS' }
            '.ssa' { 'SSA' }
            default {
                if ($content -match '\[Script Info\]') { 'ASS' } else { 'SRT' }
            }
        }

        $warnings = @{}
        $file     = switch ($format) {
            'SRT' {
                $f           = [SubtitleFile]::new()
                $f.Format    = 'SRT'
                $f.Entries   = Invoke-SrtParser -Content $content -Warnings $warnings
                $f
            }
            { $_ -in 'ASS', 'SSA' } {
                Invoke-AssParser -Content $content -Warnings $warnings
            }
        }

        $file.Path           = $resolvedPath
        $file.Encoding       = $encodingInfo.Name
        $file.HasBom         = $encodingInfo.HasBom
        $file.ParserWarnings = $warnings

        if ($warnings.Count -gt 0) {
            Write-SubtitleLog -Message ("Parsed '$resolvedPath' with $($warnings.Count) warning(s).") -Level Warning
            foreach ($key in $warnings.Keys) {
                Write-SubtitleLog -Message $warnings[$key] -Level Warning
            }
        }

        return $file
    }
}
