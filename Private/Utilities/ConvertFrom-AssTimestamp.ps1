function ConvertFrom-AssTimestamp {
    <#
    .SYNOPSIS
        Converts an ASS timestamp string to a TimeSpan.
    .DESCRIPTION
        ASS format is H:mm:ss.cc where cc is centiseconds (hundredths of a second).
    #>
    [OutputType([TimeSpan])]
    param(
        [Parameter(Mandatory)]
        [string] $Timestamp
    )

    $t = $Timestamp.Trim()

    if ($t -match '^(\d+):(\d{2}):(\d{2})\.(\d{2})$') {
        $h  = [int]$Matches[1]
        $m  = [int]$Matches[2]
        $s  = [int]$Matches[3]
        $cs = [int]$Matches[4]   # centiseconds
        return [TimeSpan]::new($h, $m, $s) + [TimeSpan]::FromMilliseconds($cs * 10)
    }

    throw "Invalid ASS timestamp format: '$Timestamp'. Expected H:mm:ss.cc"
}
