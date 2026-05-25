function ConvertFrom-SrtTimestamp {
    <#
    .SYNOPSIS
        Converts an SRT timestamp string to a TimeSpan.
    .DESCRIPTION
        Accepts HH:mm:ss,fff or HH:mm:ss.fff (both comma and dot separators).
    #>
    [OutputType([TimeSpan])]
    param(
        [Parameter(Mandatory)]
        [string] $Timestamp
    )

    # Normalize dot separator to comma for consistent parsing
    $normalized = $Timestamp.Trim() -replace '\.', ','

    if ($normalized -match '^(\d{2}):(\d{2}):(\d{2}),(\d{3})$') {
        $h   = [int]$Matches[1]
        $m   = [int]$Matches[2]
        $s   = [int]$Matches[3]
        $ms  = [int]$Matches[4]
        return [TimeSpan]::new($h, $m, $s) + [TimeSpan]::FromMilliseconds($ms)
    }

    throw "Invalid SRT timestamp format: '$Timestamp'. Expected HH:mm:ss,fff"
}
