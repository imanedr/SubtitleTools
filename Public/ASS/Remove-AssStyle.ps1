function Remove-AssStyle {
    <#
    .SYNOPSIS
        Removes a style from an ASS SubtitleFile by name.
    .DESCRIPTION
        Also updates any entries that referenced the removed style to use 'Default',
        unless -LeaveEntries is specified.
    .PARAMETER InputObject
        A SubtitleFile with ASS format.
    .PARAMETER Name
        Name of the style to remove.
    .PARAMETER LeaveEntries
        Do not reassign entries that reference the removed style.
    .EXAMPLE
        Import-SubtitleFile 'anime.ass' | Remove-AssStyle -Name 'OldStyle'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject,

        [Parameter(Mandatory)]
        [string] $Name,

        [switch] $LeaveEntries
    )

    process {
        if (-not $InputObject.Header) {
            throw 'SubtitleFile has no Header.'
        }

        $existing = $InputObject.Header.Styles | Where-Object { $_.Name -eq $Name }
        if (-not $existing) {
            Write-Warning “Style '$Name' not found — nothing to remove.”
            return $InputObject
        }

        if ($PSCmdlet.ShouldProcess($Name, 'Remove ASS style')) {
            $InputObject.Header.Styles = @($InputObject.Header.Styles | Where-Object { $_.Name -ne $Name })

            if (-not $LeaveEntries) {
                foreach ($entry in $InputObject.Entries) {
                    if ($entry -is [AssEntry] -and $entry.Style -eq $Name) {
                        $entry.Style = 'Default'
                    }
                }
            }
        }

        return $InputObject
    }
}
