function Find-SubtitleFile {
    <#
    .SYNOPSIS
        Recursively finds subtitle files in a directory.
    .DESCRIPTION
        Searches for .srt, .ass, and .ssa files. Optionally filters by format or pattern.
    .PARAMETER Path
        Root directory to search. Defaults to current directory.
    .PARAMETER Format
        Filter by format: 'SRT', 'ASS', 'SSA', or 'All'.
    .PARAMETER Pattern
        Wildcard pattern to match filenames (e.g., '*english*').
    .PARAMETER Recurse
        Search subdirectories recursively.
    .EXAMPLE
        Find-SubtitleFile -Path 'D:\Movies' -Recurse
    .EXAMPLE
        Find-SubtitleFile -Format SRT -Pattern '*english*' -Recurse
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param(
        [string] $Path = '.',

        [ValidateSet('SRT', 'ASS', 'SSA', 'All')]
        [string] $Format = 'All',

        [string] $Pattern = '*',

        [switch] $Recurse
    )

    $extensions = switch ($Format) {
        'SRT' { @('.srt') }
        'ASS' { @('.ass') }
        'SSA' { @('.ssa') }
        'All' { @('.srt', '.ass', '.ssa') }
    }

    $splat = @{
        Path    = $Path
        Filter  = $Pattern
        File    = $true
        Recurse = $Recurse.IsPresent
    }

    Get-ChildItem @splat | Where-Object {
        $extensions -contains $_.Extension.ToLower()
    }
}
