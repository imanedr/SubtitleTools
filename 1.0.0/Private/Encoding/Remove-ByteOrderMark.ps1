function Remove-ByteOrderMark {
    <#
    .SYNOPSIS
        Removes the byte order mark from the beginning of a string if present.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    if ($Text.Length -gt 0 -and [int][char]$Text[0] -eq 0xFEFF) {
        return $Text.Substring(1)
    }
    return $Text
}
