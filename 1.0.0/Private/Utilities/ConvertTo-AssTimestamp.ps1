function ConvertTo-AssTimestamp {
    <#
    .SYNOPSIS
        Converts a TimeSpan to an ASS timestamp string (H:mm:ss.cc).
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [TimeSpan] $TimeSpan
    )

    $h  = [int][Math]::Floor($TimeSpan.TotalHours)
    $m  = $TimeSpan.Minutes
    $s  = $TimeSpan.Seconds
    $cs = [int][Math]::Floor($TimeSpan.Milliseconds / 10)

    return '{0}:{1:D2}:{2:D2}.{3:D2}' -f $h, $m, $s, $cs
}
