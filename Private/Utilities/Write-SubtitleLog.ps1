function Write-SubtitleLog {
    <#
    .SYNOPSIS
        Writes a structured log message — to console and optionally to a file.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Message,

        [ValidateSet('Info', 'Warning', 'Error', 'Debug')]
        [string] $Level = 'Info',

        [string] $LogPath
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line      = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'Warning' { Write-Warning $Message }
        'Error'   { Write-Error   $Message }
        'Debug'   { Write-Debug   $Message }
        default   { Write-Verbose $Message }
    }

    if ($LogPath) {
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
    }
}
