function ConvertTo-Gif
{
    <#
        .SYNOPSIS
            Convert a video to an animated GIF, using ffmpeg

        .DESCRIPTION
            Makes a GIF in one ffmpeg pass. The video is cut to -Start and -End, reduced to -Fps frames
            per second and scaled to -Width. Then a palette is made from the colours actually used, and the
            frames are mapped onto it. Building the palette from frame differences (stats_mode=diff) keeps
            colours for the parts that move, which suits screen recordings.

            -RemoveDuplicateFrames drops frames that look the same as the one before. Screen and terminal
            recordings are mostly pauses, so this often shrinks the file a lot. The pauses are kept as longer
            frame delays, so playback timing doesn't change. One frame is still kept every half second
            through a pause, so a pause at the very end of the video isn't cut short.

            The source can be anything ffmpeg reads, not just MP4.

            Returns the GIF as a file object.

        .NOTES
            Author: Adrian Andersson

            The convert-mp4togif alias, and the mp4Path and gifPath parameter aliases, keep version 1
            scripts working.

        .EXAMPLE
            ConvertTo-Gif -Path .\demo.mp4

            #### DESCRIPTION
            Make demo.gif next to demo.mp4, at 10 frames per second and at most 800 pixels wide.

        .EXAMPLE
            ConvertTo-Gif -Path .\demo.mp4 -Destination .\docs\demo.gif -Width 640 -Fps 15 -Start 2 -End 1:30 -RemoveDuplicateFrames

            #### DESCRIPTION
            Make a 640 pixel wide GIF from 2 seconds to 1 minute 30, dropping frames where nothing changes.

        .EXAMPLE
            Get-ChildItem .\recordings\*.mkv | ConvertTo-Gif -Force

            #### DESCRIPTION
            Convert every MKV in a folder, overwriting any GIFs already there.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [Alias('convert-mp4togif')]
    [OutputType([System.IO.FileInfo])]
    PARAM(
        #Video to convert. Accepts pipeline input, including from Get-ChildItem
        [Parameter(Mandatory,Position=0,ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [Alias('FullName','mp4Path')]
        [string]$Path,
        #Where to save the GIF: a file, or a folder to save it in. Defaults to the video's folder and name, with a .gif extension
        [Parameter(Position=1)]
        [Alias('gifPath')]
        [string]$Destination,
        #Frames per second. GIF timing is in hundredths of a second, so rates above 50 are not reliable
        [Parameter()]
        [ValidateRange(1,50)]
        [int]$Fps = 10,
        #Width in pixels, keeping the aspect ratio. Videos narrower than this are not enlarged. 0 keeps the video's width
        [Parameter()]
        [ValidateRange(0,7680)]
        [int]$Width = 800,
        #Where to start: seconds (5), mm:ss (1:30) or hh:mm:ss
        [Parameter()]
        [ToTimeSpan()]
        [timespan]$Start,
        #Where to stop: seconds (5), mm:ss (1:30) or hh:mm:ss
        [Parameter()]
        [ToTimeSpan()]
        [timespan]$End,
        #Drop frames that look the same as the one before, keeping the timing
        [Parameter()]
        [switch]$RemoveDuplicateFrames,
        #Most colours in the palette. Fewer colours make a smaller file
        [Parameter()]
        [ValidateRange(2,256)]
        [int]$MaxColors = 256,
        #How to blend colours the palette doesn't have. Bayer is smaller and suits flat screen content; Sierra2_4a is ffmpeg's default and looks smoother
        [Parameter()]
        [ValidateSet('Sierra2_4a','Sierra2','FloydSteinberg','Bayer','None')]
        [string]$Dither = 'Sierra2_4a',
        #How many times to play. 0 loops forever, -1 plays once, any other number repeats that many times
        [Parameter()]
        [ValidateRange(-1,65535)]
        [int]$Loop = 0,
        #Overwrite the GIF if it already exists
        [Parameter()]
        [switch]$Force
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"

        $culture = [cultureinfo]::InvariantCulture
        $ditherNames = @{
            Sierra2_4a = 'sierra2_4a'
            Sierra2 = 'sierra2'
            FloydSteinberg = 'floyd_steinberg'
            Bayer = 'bayer'
            None = 'none'
        }

        if($PSBoundParameters.ContainsKey('Start') -and $Start -lt [timespan]::Zero)
        {
            throw 'Start cannot be negative'
        }
        if($PSBoundParameters.ContainsKey('End') -and $End -le [timespan]::Zero)
        {
            throw 'End must be after the start of the video'
        }
        if($PSBoundParameters.ContainsKey('Start') -and $PSBoundParameters.ContainsKey('End') -and $End -le $Start)
        {
            throw "End ($End) must be after Start ($Start)"
        }
    }
    process{
        $sourceFile = Get-Item -LiteralPath $Path -ErrorAction Ignore
        if(!$sourceFile -or $sourceFile.PSIsContainer)
        {
            Write-Error "Video file not found: $Path"
            return
        }
        write-verbose "Source: $($sourceFile.FullName)"

        $gifName = "$([System.IO.Path]::GetFileNameWithoutExtension($sourceFile.Name)).gif"
        if(!$Destination)
        {
            $destinationPath = Join-Path -Path $sourceFile.DirectoryName -ChildPath $gifName
        }elseif(Test-Path -LiteralPath $Destination -PathType Container){
            $destinationPath = Join-Path -Path (Get-Item -LiteralPath $Destination).FullName -ChildPath $gifName
        }else{
            $destinationPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
        }
        write-verbose "Destination: $destinationPath"

        if($destinationPath -eq $sourceFile.FullName)
        {
            Write-Error "The destination is the same file as the source: $destinationPath"
            return
        }
        if((Test-Path -LiteralPath $destinationPath) -and !$Force)
        {
            Write-Error "$destinationPath already exists. Use -Force to overwrite it"
            return
        }
        $destinationFolder = Split-Path -Path $destinationPath -Parent
        if(!(Test-Path -LiteralPath $destinationFolder -PathType Container))
        {
            Write-Error "The destination folder does not exist: $destinationFolder"
            return
        }

        $filters = [System.Collections.Generic.List[string]]::new()
        $filters.Add("fps=$Fps")
        if($RemoveDuplicateFrames)
        {
            #A GIF's last frame has no next frame to set its delay, so a pause at the very end would be lost.
            #Keeping one frame in every half second of a pause bounds that to half a second, and still drops most frames
            $filters.Add("mpdecimate=max=$([math]::Max(1,[int][math]::Floor($Fps / 2)))")
        }
        if($Width -gt 0)
        {
            #The quotes stop ffmpeg reading the comma in min() as the end of the filter
            $filters.Add("scale='min($Width,iw)':-1:flags=lanczos")
        }
        $paletteUse = "paletteuse=dither=$($ditherNames[$Dither])"
        if($Dither -eq 'Bayer')
        {
            $paletteUse = "${paletteUse}:bayer_scale=3"
        }
        $filterGraph = "[0:v]$($filters -join ','),split[a][b];[a]palettegen=max_colors=$($MaxColors):stats_mode=diff[p];[b][p]$($paletteUse):diff_mode=rectangle"
        write-verbose "Filter graph: $filterGraph"

        $ffmpegArguments = [System.Collections.Generic.List[string]]::new()
        $ffmpegArguments.AddRange([string[]]@('-hide_banner','-loglevel','error','-y'))
        if($PSBoundParameters.ContainsKey('Start') -and $Start -gt [timespan]::Zero)
        {
            $ffmpegArguments.AddRange([string[]]@('-ss',$Start.TotalSeconds.ToString($culture)))
        }
        if($PSBoundParameters.ContainsKey('End'))
        {
            $length = $(if($PSBoundParameters.ContainsKey('Start')){$End - $Start}else{$End})
            $ffmpegArguments.AddRange([string[]]@('-t',$length.TotalSeconds.ToString($culture)))
        }
        $ffmpegArguments.AddRange([string[]]@('-i',$sourceFile.FullName,'-filter_complex',$filterGraph))
        if($RemoveDuplicateFrames)
        {
            #Keep each frame's own timestamp, so dropped frames become longer delays instead of a faster GIF
            $ffmpegArguments.AddRange([string[]]@('-fps_mode','vfr'))
        }
        $ffmpegArguments.AddRange([string[]]@('-loop',[string]$Loop,'-f','gif',$destinationPath))

        if($PSCmdlet.ShouldProcess($destinationPath, "Create GIF from $($sourceFile.Name)"))
        {
            $invokeSplat = @{
                ArgumentList = $ffmpegArguments
                ProgressActivity = "Converting $($sourceFile.Name) to GIF"
                ErrorAction = 'Stop'
            }
            #The expected length is only for the progress bar, so carry on without it if ffprobe can't help
            $expectedDuration = $null
            if($PSBoundParameters.ContainsKey('End'))
            {
                $expectedDuration = $(if($PSBoundParameters.ContainsKey('Start')){$End - $Start}else{$End})
            }else{
                try{
                    $sourceDuration = (Get-VideoMetadata -Path $sourceFile.FullName -ErrorAction Stop).Duration
                    if($sourceDuration)
                    {
                        $expectedDuration = $(if($PSBoundParameters.ContainsKey('Start')){$sourceDuration - $Start}else{$sourceDuration})
                    }
                }catch{
                    write-verbose "Unable to read the source duration, so progress will not show a percentage: $($_.Exception.Message)"
                }
            }
            if($expectedDuration -and $expectedDuration -gt [timespan]::Zero)
            {
                $invokeSplat.ExpectedDuration = $expectedDuration
            }

            try{
                $null = Invoke-FFmpeg @invokeSplat
            }catch{
                Write-Error "Unable to convert $($sourceFile.FullName) to a GIF: $($_.Exception.Message)"
                return
            }
            Get-Item -LiteralPath $destinationPath
        }
    }
}
