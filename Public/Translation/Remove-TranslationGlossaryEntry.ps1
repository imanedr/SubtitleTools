function Remove-TranslationGlossaryEntry {
    <#
    .SYNOPSIS
        Removes one or more terms from a translation glossary file.
    .PARAMETER Path
        Path to the glossary JSON file.
    .PARAMETER SourceTerm
        The source term(s) to remove. Accepts wildcards.
    .EXAMPLE
        Remove-TranslationGlossaryEntry -Path './glossary.json' -SourceTerm 'Stark'
    .EXAMPLE
        Remove-TranslationGlossaryEntry -Path './glossary.json' -SourceTerm 'Dr.*'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $SourceTerm
    )

    if (-not (Test-Path $Path)) {
        throw "Glossary file not found: '$Path'"
    }

    $existingObj = Get-Content $Path -Raw | ConvertFrom-Json
    $existing    = @{}
    foreach ($propName in ($existingObj | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Name) {
        $existing[$propName] = $existingObj.$propName
    }
    $toRemove = $existing.Keys | Where-Object { $_ -like $SourceTerm }

    if ($toRemove.Count -eq 0) {
        Write-Warning "No terms matching '$SourceTerm' found in glossary."
        return
    }

    foreach ($term in $toRemove) {
        if ($PSCmdlet.ShouldProcess($term, 'Remove glossary entry')) {
            $existing.Remove($term)
            Write-Verbose "Removed: '$term'"
        }
    }

    $existing | ConvertTo-Json -Depth 2 | Set-Content $Path -Encoding UTF8
}
