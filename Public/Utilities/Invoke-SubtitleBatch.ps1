function Invoke-SubtitleBatch {
    <#
    .SYNOPSIS
        Applies a subtitle operation to multiple files in a directory.
    .DESCRIPTION
        Finds all subtitle files matching the specified format/pattern and runs
        a scriptblock against each one. Supports progress reporting, logging,
        and PS 7+ parallel execution.

        The scriptblock receives a single SubtitleFile object as $_ and should
        return a SubtitleFile (or $null to skip writing output).

    .PARAMETER Path
        Root directory to search. Default: current directory.
    .PARAMETER ScriptBlock
        Operation to apply to each SubtitleFile. Receives the file as $_.
        Return a SubtitleFile to write output, or $null to skip.
    .PARAMETER Format
        Subtitle format to process: SRT, ASS, SSA, or All. Default: All.
    .PARAMETER Pattern
        Filename wildcard pattern. Default: *.
    .PARAMETER Recurse
        Search subdirectories.
    .PARAMETER OutputSuffix
        Suffix to append before the extension for output files (e.g. '_fixed').
        If omitted, the original file is overwritten.
    .PARAMETER LogPath
        Path to a log file for operation results.
    .PARAMETER ThrottleLimit
        Maximum parallel threads (PowerShell 7+ only). Default: 4.
    .PARAMETER Parallel
        Use ForEach-Object -Parallel (requires PowerShell 7+).
    .EXAMPLE
        # Fix encoding on all SRT files recursively
        Invoke-SubtitleBatch -Path 'D:\Movies' -Recurse -Format SRT -ScriptBlock {
            $_ | Repair-SubtitleEncoding
        }
    .EXAMPLE
        # Shift all subtitles by 2 seconds, save to new file
        Invoke-SubtitleBatch -Path '.' -OutputSuffix '_shifted' -ScriptBlock {
            $_ | Add-SubtitleOffset -Seconds 2
        }
    #>
    [CmdletBinding()]
    param(
        [string] $Path = '.',

        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock,

        [ValidateSet('SRT', 'ASS', 'SSA', 'All')]
        [string] $Format = 'All',

        [string] $Pattern = '*',

        [switch] $Recurse,

        [string] $OutputSuffix,

        [string] $LogPath,

        [int] $ThrottleLimit = 4,

        [switch] $Parallel
    )

    $files = Find-SubtitleFile -Path $Path -Format $Format -Pattern $Pattern -Recurse:$Recurse

    if ($files.Count -eq 0) {
        Write-Warning "No subtitle files found in '$Path'."
        return
    }

    $total    = $files.Count
    $done     = 0
    $success  = 0
    $failed   = 0
    $results  = [System.Collections.Generic.List[PSCustomObject]]::new()

    if ($Parallel -and $PSVersionTable.PSVersion.Major -ge 7) {
        $fileList = $files.FullName
        $fileList | ForEach-Object -Parallel {
            $filePath = $_
            try {
                $sub    = Import-SubtitleFile -Path $filePath
                $output = $sub | & $using:ScriptBlock
                if ($output) {
                    $suffix   = $using:OutputSuffix
                    $destPath = if ($suffix) {
                        $base = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
                        $ext  = [System.IO.Path]::GetExtension($filePath)
                        $dir  = [System.IO.Path]::GetDirectoryName($filePath)
                        Join-Path $dir ($base + $suffix + $ext)
                    } else { $filePath }

                    Export-SubtitleFile -InputObject $output -Path $destPath
                }
                [PSCustomObject]@{ File = $filePath; Status = 'OK'; Error = '' }
            } catch {
                [PSCustomObject]@{ File = $filePath; Status = 'FAILED'; Error = $_.Exception.Message }
            }
        } -ThrottleLimit $ThrottleLimit
        return
    }

    # Sequential with progress
    foreach ($file in $files) {
        $done++
        Write-Progress -Activity 'Processing subtitle files' `
            -Status "$done / $total : $($file.Name)" `
            -PercentComplete ([int](($done / $total) * 100))

        try {
            $sub    = Import-SubtitleFile -Path $file.FullName
            $output = & $ScriptBlock $sub

            if ($output) {
                $destPath = if ($OutputSuffix) {
                    $base = [System.IO.Path]::GetFileNameWithoutExtension($file.FullName)
                    $ext  = [System.IO.Path]::GetExtension($file.FullName)
                    Join-Path $file.DirectoryName ($base + $OutputSuffix + $ext)
                } else { $file.FullName }

                Export-SubtitleFile -InputObject $output -Path $destPath
            }

            $success++
            $record = [PSCustomObject]@{ File = $file.FullName; Status = 'OK'; Error = '' }
        } catch {
            $failed++
            Write-Warning "Failed: $($file.Name) — $($_.Exception.Message)"
            $record = [PSCustomObject]@{ File = $file.FullName; Status = 'FAILED'; Error = $_.Exception.Message }
        }

        $results.Add($record)

        if ($LogPath) {
            $line = '[{0}] [{1}] {2}{3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $record.Status, $file.FullName,
                (if ($record.Error) { ' -- ' + $record.Error } else { '' })
            Add-Content -Path $LogPath -Value $line -Encoding UTF8
        }
    }

    Write-Progress -Activity 'Processing subtitle files' -Completed
    Write-Verbose "Batch complete: $success succeeded, $failed failed out of $total files."

    return $results.ToArray()
}
