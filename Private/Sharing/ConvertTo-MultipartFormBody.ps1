function ConvertTo-MultipartFormBody {
    <#
    .SYNOPSIS
        Builds a multipart/form-data request body as raw bytes.
    .DESCRIPTION
        Invoke-RestMethod's -Form parameter is PowerShell 6.1+. This module targets
        5.1 (the manifest says so, and Windows PowerShell is where most users run
        it), where -Form does not exist and the call fails outright with a parameter
        binding error. So the body is assembled here and passed to -Body as a byte
        array, which both editions send verbatim.

        Both editions deliberately use this same path rather than -Form on 7 and
        this on 5.1: a branch that only ever executes on an edition the maintainer
        cannot run is a branch that rots untested.

        The body is accumulated in a MemoryStream rather than concatenated as a
        string. A subtitle file is arbitrary bytes - it may be UTF-16, contain a
        BOM, or carry a lone 0x00 - and round-tripping those through a [string]
        would silently rewrite them. Only the headers and text fields are encoded
        (as UTF-8, matching RFC 7578); the file's own bytes are copied through
        untouched.
    .PARAMETER Fields
        Text form fields, name -> value. Pass an [ordered] dictionary to control
        the order parts appear in the body.
    .PARAMETER FilePath
        Optional file to attach as a binary part.
    .PARAMETER FileFieldName
        Form field name for the attached file. Required when -FilePath is given.
    .OUTPUTS
        Hashtable with:
          Body        - [byte[]] the encoded request body
          ContentType - the multipart/form-data content type, carrying the boundary
                        that Body was built with. The two belong together; sending
                        one with a mismatched other yields an empty form server-side.
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        [System.Collections.IDictionary] $Fields = @{},

        [string] $FilePath,

        [string] $FileFieldName
    )

    if ($FilePath -and -not $FileFieldName) {
        throw 'ConvertTo-MultipartFormBody: -FileFieldName is required when -FilePath is supplied.'
    }

    # A GUID with no separators cannot collide with any content in the body, so no
    # scan of the payload for the boundary string is needed.
    $boundary = [Guid]::NewGuid().ToString('N')
    $crlf     = "`r`n"
    # Constructed rather than [Encoding]::UTF8 so the BOM-less intent is explicit;
    # GetBytes never emits a preamble either way.
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $stream   = [System.IO.MemoryStream]::new()

    try {
        $writeText = {
            param([string] $Text)
            $bytes = $encoding.GetBytes($Text)
            $stream.Write($bytes, 0, $bytes.Length)
        }

        foreach ($name in $Fields.Keys) {
            $value = $Fields[$name]
            if ($null -eq $value) { $value = '' }

            & $writeText ("--$boundary$crlf" +
                "Content-Disposition: form-data; name=`"$name`"$crlf$crlf" +
                "$value$crlf")
        }

        if ($FilePath) {
            $fileName  = Split-Path -Path $FilePath -Leaf
            $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)

            & $writeText ("--$boundary$crlf" +
                "Content-Disposition: form-data; name=`"$FileFieldName`"; filename=`"$fileName`"$crlf" +
                "Content-Type: application/octet-stream$crlf$crlf")

            $stream.Write($fileBytes, 0, $fileBytes.Length)
            & $writeText $crlf
        }

        & $writeText "--$boundary--$crlf"

        return @{
            Body        = $stream.ToArray()
            ContentType = "multipart/form-data; boundary=$boundary"
        }
    } finally {
        $stream.Dispose()
    }
}
