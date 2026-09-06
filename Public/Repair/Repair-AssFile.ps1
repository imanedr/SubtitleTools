function Repair-AssFile {
    <#
    .SYNOPSIS
        Repairs common issues in ASS/SSA subtitle files.
    .DESCRIPTION
        Adds missing default style if none exist. Fixes unclosed override tags.
        Returns a repaired SubtitleFile object.
    .PARAMETER InputObject
        A SubtitleFile object with Format 'ASS' or 'SSA'.
    .PARAMETER Path
        Path to an ASS/SSA file to load and repair.
    .PARAMETER OutputPath
        If specified, writes the repaired file to this path.
    .EXAMPLE
        Repair-AssFile -Path 'broken.ass' -OutputPath 'fixed.ass'
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

        # Ensure header exists
        if (-not $InputObject.Header) {
            $InputObject.Header = [AssHeader]::new()
            Write-SubtitleLog -Message 'Added missing [Script Info] header with defaults.' -Level Warning
        }

        # Ensure at least one style exists
        if ($InputObject.Header.Styles.Count -eq 0) {
            $InputObject.Header.Styles = @([AssStyle]::new())
            Write-SubtitleLog -Message 'Added default style (none were defined).' -Level Warning
        }

        # Fix unclosed override tags in entries
        foreach ($entry in $InputObject.Entries) {
            $rawText = $entry.RawText
            if ($rawText -match '\{[^}]*$') {
                $entry.RawText = $rawText + '}'
                Write-SubtitleLog -Message "Closed unclosed override tag in entry $($entry.Index)." -Level Warning
            }
        }

        if ($OutputPath) {
            if ($PSCmdlet.ShouldProcess($OutputPath, 'Write repaired ASS')) {
                Export-SubtitleFile -InputObject $InputObject -Path $OutputPath -Format ASS
            }
        }

        return $InputObject
    }
}
