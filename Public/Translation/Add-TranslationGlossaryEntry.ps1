function Add-TranslationGlossaryEntry {
    <#
    .SYNOPSIS
        Adds or updates a term in a translation glossary file.
    .DESCRIPTION
        Creates the glossary file if it does not exist.
        If the source term already exists, updates its translation unless -NoClobber is set.
    .PARAMETER Path
        Path to the glossary JSON file.
    .PARAMETER SourceTerm
        The term in the source language.
    .PARAMETER Translation
        The desired translation in the target language.
    .PARAMETER NoClobber
        Do not overwrite an existing entry for the same source term.
    .EXAMPLE
        Add-TranslationGlossaryEntry -Path './glossary.json' -SourceTerm 'Stark' -Translation 'استارک'
    .EXAMPLE
        Add-TranslationGlossaryEntry -Path './glossary.json' -SourceTerm 'Shield' -Translation 'سپر' -NoClobber
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $SourceTerm,

        [Parameter(Mandatory)]
        [string] $Translation,

        [switch] $NoClobber
    )

    $glossary = @{}

    if (Test-Path $Path) {
        $existingObj = Get-Content $Path -Raw | ConvertFrom-Json
        foreach ($propName in ($existingObj | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Name) {
            $glossary[$propName] = $existingObj.$propName
        }
    }

    if ($glossary.ContainsKey($SourceTerm) -and $NoClobber) {
        Write-Verbose "Term '$SourceTerm' already exists and -NoClobber is set. No change."
        return
    }

    $glossary[$SourceTerm] = $Translation

    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $glossary | ConvertTo-Json -Depth 2 | Set-Content $Path -Encoding UTF8
    Write-Verbose "Saved: '$SourceTerm' -> '$Translation' in '$Path'."
}
