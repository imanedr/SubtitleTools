function New-SubtitleEntryCopy {
    <#
    .SYNOPSIS
        Creates a properly-typed copy of a subtitle entry with new translated lines.
    .DESCRIPTION
        PSObject.Copy() does not reliably clone PowerShell class instances — typed
        properties like [TimeSpan] can lose their type, causing downstream format errors.
        This function creates a fresh instance of the correct concrete type and copies
        all fields explicitly.
    #>
    param(
        [Parameter(Mandatory)]
        [SubtitleEntry] $Source,

        [Parameter(Mandatory)]
        [string[]] $Lines
    )

    if ($Source -is [AssEntry]) {
        $entry             = [AssEntry]::new()
        $entry.Layer       = $Source.Layer
        $entry.Style       = $Source.Style
        $entry.Name        = $Source.Name
        $entry.MarginL     = $Source.MarginL
        $entry.MarginR     = $Source.MarginR
        $entry.MarginV     = $Source.MarginV
        $entry.Effect      = $Source.Effect
        $entry.EventType   = $Source.EventType
        $entry.OverrideTags = $Source.OverrideTags
    } elseif ($Source -is [SrtEntry]) {
        $entry             = [SrtEntry]::new()
        $entry.BlockNumber = $Source.BlockNumber
        $entry.HasHtmlTags = $Source.HasHtmlTags
    } else {
        $entry             = [SubtitleEntry]::new()
    }

    $entry.Index    = $Source.Index
    $entry.Start    = $Source.Start
    $entry.End      = $Source.End
    $entry.Metadata = $Source.Metadata
    $entry.Lines    = $Lines
    $entry.RawText  = $Lines -join "`n"

    return $entry
}
