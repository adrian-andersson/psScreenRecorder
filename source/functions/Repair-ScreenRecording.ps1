function Repair-ScreenRecording
{
    <#
        .SYNOPSIS
            Turn a recording that wasn't stopped properly into a normal video file

        .DESCRIPTION
            Recordings are made into a Matroska file, '<name>.recording.mkv', next to the final file. If ffmpeg
            is ended rather than stopped, for example because the PowerShell window was closed, that file is
            left behind without its index. Most players then show no duration and can't seek, so it looks
            corrupt, though the video is all there up to the last second.

            This copies the video into a new file without re-encoding (a remux), which rebuilds the index. It
            takes moments. By default the new file is '<name>.mp4', and the left-behind file is removed once the
            new one is written.

            Get-ScreenRecording -AllSessions lists recordings left behind by other sessions, and piping them to
            Stop-ScreenRecording repairs them to the names they were going to have. This is for any other file.

            Returns the repaired file, with Duration, Width, Height, FrameRate and VideoCodec added.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Repair-ScreenRecording -Path '.\Screen Recording 2026-11-27 14-05-09.recording.mkv'

            #### DESCRIPTION
            Repair a left-behind recording into 'Screen Recording 2026-11-27 14-05-09.mp4'.

        .EXAMPLE
            Get-ChildItem ([Environment]::GetFolderPath('MyVideos')) -Filter '*.recording.mkv' | Repair-ScreenRecording

            #### DESCRIPTION
            Repair every left-behind recording in the Videos folder.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    PARAM(
        #The recording to repair. Accepts pipeline input, including from Get-ChildItem
        [Parameter(Mandatory,Position=0,ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [Alias('FullName','RecordingPath')]
        [string]$Path,
        #Where to save the repaired video. Defaults to the same name without '.recording', as .mp4. Its extension (.mp4, .mkv or .mov) sets the container
        [Parameter(Position=1)]
        [string]$Destination,
        #The video codec, if known. Read from the file otherwise
        [Parameter(DontShow)]
        [string]$Codec,
        #Keep the original file after repairing it
        [Parameter()]
        [switch]$KeepSource,
        #Overwrite the destination if it exists
        [Parameter()]
        [switch]$Force
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"
    }
    process{
        $source = Get-Item -LiteralPath $Path -ErrorAction Ignore
        if(!$source -or $source.PSIsContainer)
        {
            Write-Error "Recording not found: $Path"
            return
        }
        if($source.Length -eq 0)
        {
            Write-Error "$($source.FullName) is empty: nothing was recorded into it, so there is nothing to repair"
            return
        }

        if($Destination)
        {
            $destinationPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
        }else{
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($source.Name) -replace '\.recording$',''
            $destinationPath = Join-Path -Path $source.DirectoryName -ChildPath "$baseName.mp4"
        }
        $extension = [System.IO.Path]::GetExtension($destinationPath).ToLowerInvariant()
        if($extension -notin '.mp4','.mkv','.mov')
        {
            Write-Error "Recordings can be saved as .mp4, .mkv or .mov, not '$extension'"
            return
        }
        if($destinationPath -eq $source.FullName)
        {
            Write-Error 'The destination is the same file as the recording. Give a different -Destination'
            return
        }
        if((Test-Path -LiteralPath $destinationPath) -and !$Force)
        {
            Write-Error "$destinationPath already exists. Use -Force to overwrite it"
            return
        }

        if(!$Codec)
        {
            try{
                $Codec = (Get-VideoMetadata -Path $source.FullName -ErrorAction Stop).VideoCodec
            }catch{
                Write-Error "$($source.FullName) can't be read as a video, so it can't be repaired: $($_.Exception.Message)"
                return
            }
        }

        if(!$PSCmdlet.ShouldProcess($destinationPath, "Repair $($source.Name)"))
        {
            return
        }
        try{
            Convert-RecordingContainer -Path $source.FullName -Destination $destinationPath -Codec $Codec
        }catch{
            Write-Error "Unable to repair $($source.FullName): $($_.Exception.Message)"
            return
        }
        if(!$KeepSource)
        {
            Remove-Item -LiteralPath $source.FullName -Force -ErrorAction SilentlyContinue
        }
        Get-Item -LiteralPath $destinationPath | Add-VideoMetadataMember
    }
}
