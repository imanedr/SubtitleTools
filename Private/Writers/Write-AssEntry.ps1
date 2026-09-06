function Write-AssEntry {
    <#
    .SYNOPSIS
        Serializes a single AssEntry to an ASS Dialogue line.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AssEntry] $Entry
    )

    $startStr = ConvertTo-AssTimestamp -TimeSpan $Entry.Start
    $endStr   = ConvertTo-AssTimestamp -TimeSpan $Entry.End

    # Re-join lines with \N (ASS soft newline)
    $text = $Entry.Lines -join '\N'

    return '{0}: {1},{2},{3},{4},{5},{6},{7},{8},{9},{10}' -f `
        $Entry.EventType,
        $Entry.Layer,
        $startStr,
        $endStr,
        $Entry.Style,
        $Entry.Name,
        $Entry.MarginL,
        $Entry.MarginR,
        $Entry.MarginV,
        $Entry.Effect,
        $text
}
