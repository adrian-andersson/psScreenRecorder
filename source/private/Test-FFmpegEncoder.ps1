function Test-FFmpegEncoder
{
    <#
        .SYNOPSIS
            Check a video encoder actually works, with a three-frame test encode

        .DESCRIPTION
            Encodes three frames of a generated black video with the encoder and throws the result away.
            Returns $true if ffmpeg succeeds, $false if it doesn't.

            Hardware encoders show up in ffmpeg's encoder list whenever the build includes them, whether or
            not the machine has a GPU that supports them. Trying them is the only reliable check.

            The test frame is 640x360, as some hardware encoders refuse very small frames.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Test-FFmpegEncoder -FFmpegPath (Find-FFmpeg).FFmpegPath -Encoder 'av1_nvenc'

            #### DESCRIPTION
            Returns $false on a GPU that can't encode AV1, such as an RTX 3090.
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    PARAM(
        #Full path to ffmpeg
        [Parameter(Mandatory)]
        [string]$FFmpegPath,
        #Name of the encoder, as ffmpeg -encoders lists it
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9_\-]+$')]
        [string]$Encoder
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"
    }
    process{
        $testArguments = @(
            '-hide_banner','-loglevel','error'
            '-f','lavfi','-i','color=c=black:s=640x360:r=30'
            '-frames:v','3'
            '-c:v',$Encoder
            '-f','null','-'
        )
        try{
            $null = Invoke-FFmpeg -ExecutablePath $FFmpegPath -ArgumentList $testArguments -ErrorAction Stop
            write-verbose "$Encoder works"
            $true
        }catch{
            write-verbose "$Encoder failed: $($_.Exception.Message)"
            $false
        }
    }
}
