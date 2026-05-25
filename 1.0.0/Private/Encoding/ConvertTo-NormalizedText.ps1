function ConvertTo-NormalizedText {
    <#
    .SYNOPSIS
        Normalizes line endings to LF and strips BOM from text content.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    # Remove BOM character
    $result = Remove-ByteOrderMark -Text $Text

    # Normalize CRLF and lone CR to LF
    $result = $result -replace '\r\n', "`n"
    $result = $result -replace '\r', "`n"

    # Normalize Unicode to NFC form
    $result = $result.Normalize([System.Text.NormalizationForm]::FormC)

    return $result
}
