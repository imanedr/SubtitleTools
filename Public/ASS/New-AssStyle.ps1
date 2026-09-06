function New-AssStyle {
    <#
    .SYNOPSIS
        Adds a new style to an ASS SubtitleFile, or returns a standalone AssStyle object.
    .DESCRIPTION
        When -InputObject is provided, the new style is added to the file's Header.
        When called without -InputObject, returns a new AssStyle object with given properties.
    .PARAMETER InputObject
        Optional SubtitleFile to add the style to.
    .PARAMETER Name
        Style name (must be unique within the file).
    .PARAMETER Fontname
        Font family. Default: Arial.
    .PARAMETER Fontsize
        Font size. Default: 20.
    .PARAMETER PrimaryColour
        Primary colour in ASS ABGR hex: &H00FFFFFF&
    .PARAMETER Alignment
        Numpad alignment (1-9). Default: 2 (bottom-center).
    .PARAMETER Force
        Replace an existing style with the same name.
    .EXAMPLE
        Import-SubtitleFile 'anime.ass' | New-AssStyle -Name 'Subtitle2' -Fontsize 18
    .EXAMPLE
        $style = New-AssStyle -Name 'Custom' -Fontname 'Calibri' -Fontsize 24
    #>
    [CmdletBinding()]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(ValueFromPipeline)]
        [SubtitleFile] $InputObject,

        [Parameter(Mandatory)]
        [string]  $Name,

        [string]  $Fontname        = 'Arial',
        [int]     $Fontsize        = 20,
        [string]  $PrimaryColour   = '&H00FFFFFF&',
        [string]  $SecondaryColour = '&H000000FF&',
        [string]  $OutlineColour   = '&H00000000&',
        [string]  $BackColour      = '&H00000000&',
        [bool]    $Bold            = $false,
        [bool]    $Italic          = $false,
        [bool]    $Underline       = $false,
        [bool]    $StrikeOut       = $false,
        [decimal] $ScaleX          = 100,
        [decimal] $ScaleY          = 100,
        [decimal] $Spacing         = 0,
        [decimal] $Angle           = 0,
        [int]     $BorderStyle     = 1,
        [decimal] $Outline         = 2,
        [decimal] $Shadow          = 0,
        [int]     $Alignment       = 2,
        [int]     $MarginL         = 10,
        [int]     $MarginR         = 10,
        [int]     $MarginV         = 10,
        [int]     $Encoding        = 1,

        [switch] $Force
    )

    process {
        $style                  = [AssStyle]::new()
        $style.Name             = $Name
        $style.Fontname         = $Fontname
        $style.Fontsize         = $Fontsize
        $style.PrimaryColour    = $PrimaryColour
        $style.SecondaryColour  = $SecondaryColour
        $style.OutlineColour    = $OutlineColour
        $style.BackColour       = $BackColour
        $style.Bold             = $Bold
        $style.Italic           = $Italic
        $style.Underline        = $Underline
        $style.StrikeOut        = $StrikeOut
        $style.ScaleX           = $ScaleX
        $style.ScaleY           = $ScaleY
        $style.Spacing          = $Spacing
        $style.Angle            = $Angle
        $style.BorderStyle      = $BorderStyle
        $style.Outline          = $Outline
        $style.Shadow           = $Shadow
        $style.Alignment        = $Alignment
        $style.MarginL          = $MarginL
        $style.MarginR          = $MarginR
        $style.MarginV          = $MarginV
        $style.Encoding         = $Encoding

        if (-not $InputObject) {
            return $style
        }

        if (-not $InputObject.Header) {
            $InputObject.Header = [AssHeader]::new()
        }

        $existing = $InputObject.Header.Styles | Where-Object { $_.Name -eq $Name }
        if ($existing) {
            if ($Force) {
                $InputObject.Header.Styles = @($InputObject.Header.Styles | Where-Object { $_.Name -ne $Name })
            } else {
                throw "Style '$Name' already exists. Use -Force to replace it."
            }
        }

        $InputObject.Header.Styles += $style
        return $InputObject
    }
}
