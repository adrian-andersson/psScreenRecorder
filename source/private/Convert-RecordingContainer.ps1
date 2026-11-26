function Convert-RecordingContainer
{
    <#
        .SYNOPSIS
            Copy a recording's video into another container, without re-encoding

        .DESCRIPTION
            A remux: the video is copied as it is, so it takes moments and loses nothing. Used to turn the
            Matroska file a recording is made into into its final .mp4, .mov or .mkv, and to repair one left
            behind when ffmpeg was killed. ffmpeg reads such a file from the start and writes a new index,
            which is what was missing.

            Adds +faststart for MP4 and MOV, so the file plays while still downloading, and tags HEVC as hvc1,
            which Apple players need. Corrupt packets at the very end, where a killed ffmpeg stopped
            mid-write, are dropped rather than failing the whole file.

            Throws if ffmpeg fails.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Convert-RecordingContainer -Path .\demo.recording.mkv -Destination .\demo.mp4 -Codec HEVC

            #### DESCRIPTION
            Copy the video into demo.mp4, tagged for Apple players.
    #>

    [CmdletBinding()]
    PARAM(
        #The file to copy from
        [Parameter(Mandatory)]
        [string]$Path,
        #The file to copy to. Its extension sets the container
        [Parameter(Mandatory)]
        [string]$Destination,
        #The video codec, if known. HEVC gets the hvc1 tag in MP4 and MOV
        [Parameter()]
        [string]$Codec
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
    }
    process{
        $extension = [System.IO.Path]::GetExtension($Destination).ToLowerInvariant()
        $remuxArguments = [System.Collections.Generic.List[string]]::new()
        $remuxArguments.AddRange([string[]]@('-hide_banner','-loglevel','error','-y','-fflags','+discardcorrupt','-i',$Path,'-map','0','-c','copy'))
        if($extension -in '.mp4','.mov')
        {
            $remuxArguments.AddRange([string[]]@('-movflags','+faststart'))
            if($Codec -in 'HEVC','hevc')
            {
                $remuxArguments.AddRange([string[]]@('-tag:v','hvc1'))
            }
        }
        $remuxArguments.Add($Destination)
        $null = Invoke-FFmpeg -ArgumentList $remuxArguments -ErrorAction Stop
    }
}
