function Export-SubtitleFile {
    <#
    .SYNOPSIS
        Writes a SubtitleFile object to disk.
    .DESCRIPTION
        Defaults to UTF-8 without BOM. Use -Encoding to override.
        Use -Format to override the output format (e.g. save an ASS as SRT).
    .PARAMETER InputObject
        The SubtitleFile object to write.
    .PARAMETER Path
        Destination file path. Defaults to the object's original Path.
    .PARAMETER Format
        Output format: 'SRT' or 'ASS'. Defaults to the object's Format property.
    .PARAMETER Encoding
        Output encoding. Defaults to UTF-8 without BOM.
    .PARAMETER PassThru
        Return the SubtitleFile object after writing.
    .EXAMPLE
        $sub | Export-SubtitleFile -Path 'output.srt'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject,

        [string] $Path,

        [ValidateSet('SRT', 'ASS')]
        [string] $Format,

        [ValidateSet('UTF-8', 'UTF-8-BOM', 'UTF-16LE', 'UTF-16BE')]
        [string] $Encoding = 'UTF-8',

        [switch] $PassThru
    )

    process {
        $outputPath   = if ($Path)   { $Path }   else { $InputObject.Path }
        $outputFormat = if ($Format) { $Format } else { $InputObject.Format }

        if (-not $outputPath) {
            throw 'No output path specified and the SubtitleFile has no Path property set.'
        }

        $content = switch ($outputFormat) {
            'SRT' { ConvertTo-SrtFile -InputObject $InputObject }
            'ASS' { ConvertTo-AssFile -InputObject $InputObject }
            default { throw "Unsupported format: '$outputFormat'" }
        }

        $enc = switch ($Encoding) {
            'UTF-8'     { [System.Text.UTF8Encoding]::new($false) }
            'UTF-8-BOM' { [System.Text.UTF8Encoding]::new($true)  }
            'UTF-16LE'  { [System.Text.UnicodeEncoding]::new($false, $true) }
            'UTF-16BE'  { [System.Text.UnicodeEncoding]::new($true,  $true) }
        }

        if ($PSCmdlet.ShouldProcess($outputPath, 'Write subtitle file')) {
            $dir = [System.IO.Path]::GetDirectoryName($outputPath)
            if ($dir -and -not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            [System.IO.File]::WriteAllText($outputPath, $content, $enc)
            Write-SubtitleLog -Message "Written '$outputPath' ($outputFormat, $Encoding)." -Level Info
        }

        if ($PassThru) { return $InputObject }
    }
}
