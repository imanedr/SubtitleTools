function Set-AssStyle {
    <#
    .SYNOPSIS
        Updates properties of an existing style in an ASS SubtitleFile.
    .DESCRIPTION
        Modifies only the properties you specify. All unspecified properties retain
        their current values. Returns the modified SubtitleFile.
    .PARAMETER InputObject
        A SubtitleFile with ASS/SSA format.
    .PARAMETER Name
        Name of the style to modify (must already exist).
    .PARAMETER Fontname
        Font family name.
    .PARAMETER Fontsize
        Font size in points.
    .PARAMETER PrimaryColour
        Primary colour in ASS ABGR hex format: &HAABBGGRR&
    .PARAMETER Bold
        Bold flag.
    .PARAMETER Italic
        Italic flag.
    .PARAMETER Alignment
        Numpad-style alignment (1-9).
    .EXAMPLE
        Import-SubtitleFile 'anime.ass' | Set-AssStyle -Name 'Default' -Fontsize 24 -Bold $true
    #>
    [CmdletBinding()]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject,

        [Parameter(Mandatory)]
        [string] $Name,

        [string]  $Fontname,
        [int]     $Fontsize,
        [string]  $PrimaryColour,
        [string]  $SecondaryColour,
        [string]  $OutlineColour,
        [string]  $BackColour,
        [bool]    $Bold,
        [bool]    $Italic,
        [bool]    $Underline,
        [bool]    $StrikeOut,
        [decimal] $ScaleX,
        [decimal] $ScaleY,
        [decimal] $Spacing,
        [decimal] $Angle,
        [int]     $BorderStyle,
        [decimal] $Outline,
        [decimal] $Shadow,
        [int]     $Alignment,
        [int]     $MarginL,
        [int]     $MarginR,
        [int]     $MarginV
    )

    process {
        if (-not $InputObject.Header) {
            throw 'SubtitleFile has no Header. Is this an ASS file?'
        }

        $style = $InputObject.Header.Styles | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if (-not $style) {
            throw "Style '$Name' not found. Use New-AssStyle to create it first."
        }

        $boundParams = $PSBoundParameters
        foreach ($prop in @('Fontname','Fontsize','PrimaryColour','SecondaryColour','OutlineColour',
                            'BackColour','Bold','Italic','Underline','StrikeOut','ScaleX','ScaleY',
                            'Spacing','Angle','BorderStyle','Outline','Shadow','Alignment',
                            'MarginL','MarginR','MarginV')) {
            if ($boundParams.ContainsKey($prop)) {
                $style.$prop = $boundParams[$prop]
            }
        }

        return $InputObject
    }
}
