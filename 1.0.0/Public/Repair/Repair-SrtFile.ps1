function Repair-SrtFile {
    <#
    .SYNOPSIS
        Automatically repairs common SRT file issues.
    .DESCRIPTION
        Fixes: renumbers blocks sequentially, normalizes timestamp delimiter (. to ,),
        removes BOM, inserts missing blank lines, removes empty entries.
        Returns a repaired SubtitleFile object. Does not write to disk unless -Path is specified.
    .PARAMETER InputObject
        A SubtitleFile or SrtEntry array to repair.
    .PARAMETER Path
        Path to an SRT file to load and repair.
    .PARAMETER OutputPath
        If specified, writes the repaired file to this path.
    .EXAMPLE
        Repair-SrtFile -Path 'broken.srt' -OutputPath 'fixed.srt'
    .EXAMPLE
        Import-SubtitleFile 'broken.srt' | Repair-SrtFile
    #>
    [CmdletBinding(DefaultParameterSetName = 'Object', SupportsShouldProcess)]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Object')]
        [SubtitleFile] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string] $Path,

        [string] $OutputPath
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $InputObject = Import-SubtitleFile -Path $Path
        }

        # Repair: renumber sequentially from 1
        $fixed = Repair-SubtitleNumbering -InputObject $InputObject

        # Repair: remove entries with no text
        $fixed.Entries = @($fixed.Entries | Where-Object {
            $_.Lines.Count -gt 0 -and ($_.Lines | Where-Object { $_.Trim() })
        })

        # Re-index after potential entry removal
        $i = 1
        foreach ($entry in $fixed.Entries) {
            $entry.Index = $i++
            if ($entry -is [SrtEntry]) { $entry.BlockNumber = $entry.Index }
        }

        # Mark encoding as clean UTF-8
        $fixed.Encoding = 'UTF-8'
        $fixed.HasBom   = $false

        Write-SubtitleLog -Message "Repaired SRT: $($fixed.Entries.Count) entries after cleanup." -Level Info

        if ($OutputPath) {
            if ($PSCmdlet.ShouldProcess($OutputPath, 'Write repaired SRT')) {
                Export-SubtitleFile -InputObject $fixed -Path $OutputPath
            }
        }

        return $fixed
    }
}
