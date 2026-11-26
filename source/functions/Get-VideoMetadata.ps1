function Get-VideoMetadata
{
    <#
        .SYNOPSIS
            Get the duration, size, frame rate, codec and other details of a video file, using ffprobe

        .DESCRIPTION
            Runs ffprobe on each file and returns an object with the details most often needed: duration,
            width and height, frame rate, codec, pixel format, bitrate and file size. The full ffprobe
            stream and format information is in the Streams and Format properties.

            Works on anything ffprobe can read, including GIF, WebP, MKV and MP4.

            Most containers don't record how many frames there are. -CountFrames decodes the whole video to
            count them, which is accurate but takes about as long as playing it at high speed.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Get-VideoMetadata -Path .\demo.mp4

            #### DESCRIPTION
            Show the details of demo.mp4.

        .EXAMPLE
            Get-ChildItem *.gif | Get-VideoMetadata -CountFrames | Select-Object Name,Width,Height,FrameCount,Size

            #### DESCRIPTION
            Compare a folder of GIFs, counting the frames in each.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Metadata is a mass noun, not a plural')]
    PARAM(
        #Video file to read. Accepts pipeline input, including from Get-ChildItem
        [Parameter(Mandatory,Position=0,ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$Path,
        #Decode the whole video to count its frames
        [Parameter()]
        [switch]$CountFrames
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"
        $culture = [cultureinfo]::InvariantCulture
    }
    process{
        foreach($item in $Path)
        {
            $file = Get-Item -LiteralPath $item -ErrorAction Ignore
            if(!$file -or $file.PSIsContainer)
            {
                Write-Error "Video file not found: $item"
                continue
            }
            write-verbose "Reading: $($file.FullName)"

            $probeArguments = [System.Collections.Generic.List[string]]::new()
            $probeArguments.AddRange([string[]]@('-v','error','-print_format','json','-show_format','-show_streams'))
            if($CountFrames)
            {
                $probeArguments.AddRange([string[]]@('-count_frames','-select_streams','v:0'))
            }
            $probeArguments.Add($file.FullName)

            try{
                $result = Invoke-FFmpeg -Tool 'ffprobe' -ArgumentList $probeArguments -ErrorAction Stop
                $probe = ($result.StandardOutput -join "`n") | ConvertFrom-Json -ErrorAction Stop
            }catch{
                Write-Error "Unable to read $($file.FullName): $($_.Exception.Message)"
                continue
            }

            #Skip cover art, which ffprobe reports as a video stream
            $videoStream = $probe.streams.Where{ $_.codec_type -eq 'video' -and !($_.disposition -and $_.disposition.attached_pic -eq 1) } | Select-Object -First 1

            #Rates come as fractions like 30/1 or 30000/1001. 0/0 means unknown
            $frameRate = $null
            foreach($rate in @($videoStream.avg_frame_rate, $videoStream.r_frame_rate))
            {
                if($rate -match '^(?<num>\d+)/(?<den>\d+)$' -and [int]$Matches.den -gt 0 -and [int]$Matches.num -gt 0)
                {
                    $frameRate = [math]::Round([double]$Matches.num / [double]$Matches.den, 3)
                    break
                }
            }

            $duration = $null
            $durationText = $(if($probe.format.duration){$probe.format.duration}else{$videoStream.duration})
            if($durationText)
            {
                $duration = [timespan]::FromSeconds([double]::Parse($durationText, $culture))
            }

            $frameCount = $null
            $frameCountText = $(if($videoStream.nb_read_frames){$videoStream.nb_read_frames}else{$videoStream.nb_frames})
            if($frameCountText)
            {
                $frameCount = [long]$frameCountText
            }

            [PSCustomObject]@{
                PSTypeName = 'psScreenRecorder.VideoMetadata'
                Name = $file.Name
                Path = $file.FullName
                Duration = $duration
                Width = $(if($videoStream.width){[int]$videoStream.width})
                Height = $(if($videoStream.height){[int]$videoStream.height})
                FrameRate = $frameRate
                FrameCount = $frameCount
                VideoCodec = $videoStream.codec_name
                PixelFormat = $videoStream.pix_fmt
                Container = $probe.format.format_name
                BitRate = $(if($probe.format.bit_rate){[long]$probe.format.bit_rate})
                Size = $file.Length
                HasAudio = [bool]($probe.streams.Where{ $_.codec_type -eq 'audio' }.Count)
                Streams = $probe.streams
                Format = $probe.format
            }
        }
    }
}
