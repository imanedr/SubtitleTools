function ConvertTo-SrtTimestamp {
    <#
    .SYNOPSIS
        Converts a TimeSpan to an SRT timestamp string (HH:mm:ss,fff).
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [TimeSpan] $TimeSpan
    )

    $h  = [int][Math]::Floor($TimeSpan.TotalHours)
    $m  = $TimeSpan.Minutes
    $s  = $TimeSpan.Seconds
    $ms = $TimeSpan.Milliseconds

    return '{0:D2}:{1:D2}:{2:D2},{3:D3}' -f $h, $m, $s, $ms
}
