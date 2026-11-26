function Read-FFmpegProgress
{
    <#
        .SYNOPSIS
            Read the latest progress from a file ffmpeg is writing with -progress

        .DESCRIPTION
            With '-progress <file>', ffmpeg appends a block of key=value lines every update, ending with
            progress=continue, or progress=end when it finishes:
                frame=150
                fps=30.00
                drop_frames=0
                dup_frames=1
                out_time_us=5000000
                total_size=1234567
                speed=1.00x
                progress=continue

            Returns the last complete block, or nothing if there isn't one yet. The file is opened for reading
            while ffmpeg still has it open for writing.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Read-FFmpegProgress -Path $recording.ProgressPath

            #### DESCRIPTION
            How many frames have been recorded so far, how long for, and how many were dropped.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    PARAM(
        #The progress file
        [Parameter(Mandatory)]
        [string]$Path
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        $culture = [cultureinfo]::InvariantCulture
    }
    process{
        if(!(Test-Path -LiteralPath $Path -PathType Leaf))
        {
            return
        }
        try{
            $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try{
                $reader = [System.IO.StreamReader]::new($stream)
                $text = $reader.ReadToEnd()
            }finally{
                $stream.Dispose()
            }
        }catch{
            write-verbose "Unable to read the progress file: $($_.Exception.Message)"
            return
        }

        $current = @{}
        $latest = $null
        foreach($line in $text -split "`r?`n")
        {
            if($line -match '^(?<key>[a-z_0-9]+)=(?<value>.*)$')
            {
                $current[$Matches.key] = $Matches.value.Trim()
                if($Matches.key -eq 'progress')
                {
                    $latest = $current
                    $current = @{}
                }
            }
        }
        if(!$latest)
        {
            return
        }

        $elapsed = $null
        $outTime = $(if($latest.ContainsKey('out_time_us')){$latest.out_time_us}else{$latest.out_time_ms})
        $outTimeValue = 0L
        if($outTime -and [long]::TryParse($outTime, [ref]$outTimeValue) -and $outTimeValue -ge 0)
        {
            $elapsed = [timespan]::FromTicks($outTimeValue * 10)
        }
        $fpsValue = 0.0
        $speedValue = 0.0
        [PSCustomObject]@{
            PSTypeName = 'psScreenRecorder.FFmpegProgress'
            Frame = $(if($latest.frame){[long]$latest.frame})
            Fps = $(if([double]::TryParse([string]$latest.fps, [System.Globalization.NumberStyles]::Float, $culture, [ref]$fpsValue)){$fpsValue})
            DroppedFrames = $(if($latest.drop_frames){[long]$latest.drop_frames}else{0})
            DuplicatedFrames = $(if($latest.dup_frames){[long]$latest.dup_frames}else{0})
            Elapsed = $elapsed
            Size = $(if($latest.total_size -match '^\d+$'){[long]$latest.total_size})
            Speed = $(if([double]::TryParse(([string]$latest.speed).TrimEnd('x'), [System.Globalization.NumberStyles]::Float, $culture, [ref]$speedValue)){$speedValue})
            Finished = ($latest.progress -eq 'end')
        }
    }
}
