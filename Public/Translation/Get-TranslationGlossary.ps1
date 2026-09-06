function Get-TranslationGlossary {
    <#
    .SYNOPSIS
        Reads and displays entries from a translation glossary file.
    .DESCRIPTION
        A glossary is a JSON file mapping source terms to target translations.
        It is injected into the AI system prompt during Invoke-SubtitleTranslation.
    .PARAMETER Path
        Path to the glossary JSON file.
    .PARAMETER Filter
        Optional wildcard pattern to filter source terms.
    .EXAMPLE
        Get-TranslationGlossary -Path './glossary.json'
    .EXAMPLE
        Get-TranslationGlossary -Path './glossary.json' -Filter 'Dr.*'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [string] $Filter
    )

    if (-not (Test-Path $Path)) {
        throw "Glossary file not found: '$Path'"
    }

    $glossary = Get-Content $Path -Raw | ConvertFrom-Json -AsHashtable

    $entries = $glossary.GetEnumerator() | ForEach-Object {
        [PSCustomObject]@{ SourceTerm = $_.Key; Translation = $_.Value }
    } | Sort-Object SourceTerm

    if ($Filter) {
        $entries = $entries | Where-Object { $_.SourceTerm -like $Filter }
    }

    return $entries
}
