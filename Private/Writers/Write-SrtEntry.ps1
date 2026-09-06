function Write-SrtEntry {
    <#
    .SYNOPSIS
        Serializes a single SrtEntry to SRT block text.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [SrtEntry] $Entry
    )

    $sb        = [System.Text.StringBuilder]::new()
    $timestamp = '{0} --> {1}' -f (ConvertTo-SrtTimestamp $Entry.Start), (ConvertTo-SrtTimestamp $Entry.End)
    [void]$sb.AppendLine($Entry.Index)
    [void]$sb.AppendLine($timestamp)

    foreach ($line in $Entry.Lines) {
        [void]$sb.AppendLine([string]$line)
    }

    return $sb.ToString()
}
