function Start-ScreenRecording
{
    <#
        .SYNOPSIS
            Record a monitor, a window, the current terminal or a region of the screen, using ffmpeg

        .DESCRIPTION
            Starts ffmpeg recording, and returns a recording you can check with Get-ScreenRecording and stop
            with Stop-ScreenRecording. With -Wait, or a focus mode, it waits for the recording to finish and
            returns the saved file instead.

            What to record:
              -Monitor <n>        a monitor, by its Index from Get-CaptureTarget. The default is the primary monitor
              -Window <name>      a window whose title or process name matches (Windows only)
              -CurrentTerminal    the terminal window this command is typed into (Windows only)
              -Rectangle x,y,w,h  an area of the screen, in physical pixels
              a capture target    piped from Get-CaptureTarget

            When to start and stop:
              -Delay              wait this long before starting
              -Duration           stop after this long
              -Wait               wait until -Duration is up, or until Q, Enter or Escape is pressed
              -StartOnFocusLoss   wait until you switch away from this window, then -Delay (2 seconds
                                  unless given), then start (Windows only)
              -StopOnFocusReturn  stop when you switch back to this window (Windows only)

            How it's recorded:
              -Quality            High (default), Standard, or Lossless (exact RGB, large, in .mkv)
              -Codec              H264 (default, plays everywhere), HEVC or AV1
              -Encoder            Auto (default: hardware first), Software, Nvenc, Qsv, Amf, MediaFoundation, VideoToolbox
              -Fps                frames per second, 30 by default
              -HideCursor         leave the mouse pointer out

            Coordinates are physical pixels, the same as Get-CaptureTarget reports, so screen scaling doesn't
            move or shrink what's recorded. ffmpeg is chosen and checked by Find-FFmpeg, and the best capture
            source the build has is used (see Get-Help Select-CaptureBackend in the source for the details).

            While recording, video goes into '<name>.recording.mkv' next to the final file. Matroska stays
            readable even if ffmpeg is killed, so a crash or power cut doesn't lose the recording. When it's
            stopped, it's copied into the final container without re-encoding, which takes moments.

            Recordings are saved in your Videos folder as 'Screen Recording <date> <time>.mp4' unless -Path is
            given. -Path can be a file or a folder; its extension (.mp4, .mkv or .mov) sets the container.

        .NOTES
            Author: Adrian Andersson

            Recording a window or the current terminal uses Windows.Graphics.Capture when ffmpeg has it
            (ffmpeg 8.1 or later), which records the window even when something covers it. With older builds,
            the window's area of the screen is recorded instead, including anything on top of it.

        .EXAMPLE
            $recording = Start-ScreenRecording
            # ...do the thing you want to record...
            Stop-ScreenRecording

            #### DESCRIPTION
            Record the primary monitor until stopped, and save it in the Videos folder.

        .EXAMPLE
            Start-ScreenRecording -CurrentTerminal -StartOnFocusLoss -StopOnFocusReturn

            #### DESCRIPTION
            Wait until you switch to another window, record this terminal's window from two seconds later,
            and stop and save when you switch back. Handy for recording a demo in another app.

        .EXAMPLE
            Start-ScreenRecording -Window '*Visual Studio Code*' -Duration 30 -Wait -Path .\demo.mp4 | ConvertTo-Gif -RemoveDuplicateFrames

            #### DESCRIPTION
            Record a VS Code window for 30 seconds, then make a GIF of it.

        .EXAMPLE
            Start-ScreenRecording -Rectangle 100,100,1280,720 -Delay 3 -Wait -Quality Lossless

            #### DESCRIPTION
            After a three second countdown, record a 1280x720 area until Q is pressed, losslessly, into an .mkv.
    #>

    [CmdletBinding(DefaultParameterSetName='Monitor',SupportsShouldProcess)]
    [OutputType([PSCustomObject],[System.IO.FileInfo])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'An instruction to the person at the console in -StartOnFocusLoss, not data')]
    PARAM(
        #Monitor to record, by its Index from Get-CaptureTarget. The default is the primary monitor
        [Parameter(ParameterSetName='Monitor',Position=0)]
        [ValidateRange(0,64)]
        [int]$Monitor,
        #Window to record: its title or process name. Wildcards are allowed; without any, it matches anywhere in the title
        [Parameter(Mandatory,ParameterSetName='Window')]
        [SupportsWildcards()]
        [string]$Window,
        #Record the terminal window this command is typed into
        [Parameter(Mandatory,ParameterSetName='CurrentTerminal')]
        [switch]$CurrentTerminal,
        #Area to record, as X,Y,Width,Height in physical pixels. Width and height are rounded down to even numbers
        [Parameter(Mandatory,ParameterSetName='Rectangle')]
        [ValidateCount(4,4)]
        [int[]]$Rectangle,
        #What to record, from Get-CaptureTarget
        [Parameter(Mandatory,ParameterSetName='Target',ValueFromPipeline)]
        [PSTypeName('psScreenRecorder.CaptureTarget')]
        [PSCustomObject]$Target,
        #Record a generated test pattern instead of the screen. Used by tests
        [Parameter(Mandatory,ParameterSetName='Synthetic',DontShow)]
        [switch]$Synthetic,
        #File or folder to save to. Defaults to the Videos folder
        [Parameter()]
        [string]$Path,
        #Frames per second
        [Parameter()]
        [ValidateRange(1,120)]
        [int]$Fps = 30,
        #High, Standard, or Lossless
        [Parameter()]
        [ValidateSet('High','Standard','Lossless')]
        [string]$Quality = 'High',
        #Video codec
        [Parameter()]
        [ValidateSet('H264','HEVC','AV1')]
        [string]$Codec = 'H264',
        #Encoder family. Auto uses hardware when it works, then software
        [Parameter()]
        [ValidateSet('Auto','Software','Nvenc','Qsv','Amf','MediaFoundation','VideoToolbox')]
        [string]$Encoder = 'Auto',
        #ffmpeg capture source. Auto chooses the best one the build has
        [Parameter()]
        [ValidateSet('Auto','gfxcapture','ddagrab','gdigrab','avfoundation','x11grab')]
        [string]$Backend = 'Auto',
        #Leave the mouse pointer out of the recording
        [Parameter()]
        [switch]$HideCursor,
        #Wait this long before starting: seconds (5), mm:ss or hh:mm:ss
        [Parameter()]
        [ToTimeSpan()]
        [timespan]$Delay,
        #Stop after this long: seconds (30), mm:ss (1:30) or hh:mm:ss
        [Parameter()]
        [ToTimeSpan()]
        [timespan]$Duration,
        #Wait for the recording to finish, and return the saved file
        [Parameter()]
        [switch]$Wait,
        #Start when you switch away from this window (Windows only)
        [Parameter()]
        [switch]$StartOnFocusLoss,
        #Stop when you switch back to this window (Windows only)
        [Parameter()]
        [switch]$StopOnFocusReturn,
        #Overwrite the file if it exists
        [Parameter()]
        [switch]$Force,
        #Use this ffmpeg encoder by name, with no settings, instead of choosing one. For advanced use
        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9_\-]+$')]
        [string]$VideoEncoder,
        #Extra ffmpeg arguments, added before the capture input. For advanced use
        [Parameter()]
        [string[]]$FFmpegInputArgument,
        #Extra ffmpeg arguments, added before the output file. For advanced use
        [Parameter()]
        [string[]]$FFmpegOutputArgument
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"

        if(!$script:psScreenRecorderRecordings)
        {
            $script:psScreenRecorderRecordings = [System.Collections.Generic.List[object]]::new()
        }
        $culture = [cultureinfo]::InvariantCulture
        $syntheticSize = @{ Width = 640; Height = 360 }
        $startupWait = [timespan]::FromSeconds(3)
        $defaultFocusDelay = [timespan]::FromSeconds(2)
        $displayProperties = [System.Management.Automation.PSPropertySet]::new('DefaultDisplayPropertySet', [string[]]@('Id','State','TargetName','Elapsed','Frames','DroppedFrames','Path'))
    }
    process{
        $usesFocus = $StartOnFocusLoss -or $StopOnFocusReturn
        if($usesFocus -and !$IsWindows)
        {
            throw '-StartOnFocusLoss and -StopOnFocusReturn are only supported on Windows for now'
        }
        $blocking = $Wait -or $usesFocus
        if($blocking -and !$StopOnFocusReturn -and !$PSBoundParameters.ContainsKey('Duration') -and [Console]::IsInputRedirected)
        {
            throw 'There is no console to press a key in, so -Wait needs -Duration to know when to stop'
        }
        if($PSBoundParameters.ContainsKey('Duration') -and $Duration -le [timespan]::Zero)
        {
            throw 'Duration must be more than zero'
        }
        if($PSBoundParameters.ContainsKey('Delay') -and $Delay -lt [timespan]::Zero)
        {
            throw 'Delay cannot be negative'
        }

        #The terminal has focus now, as the command was just typed into it
        $terminalHandle = $null
        if($usesFocus)
        {
            $terminalHandle = Get-TerminalWindowHandle
        }

        write-verbose 'Working out what to record'
        $monitors = @()
        if($PSCmdlet.ParameterSetName -ne 'Synthetic')
        {
            $monitors = @(Get-CaptureTarget)
        }
        $captureTarget = switch($PSCmdlet.ParameterSetName)
        {
            'Monitor' {
                if(!$monitors)
                {
                    throw 'No monitors were found to record'
                }
                if($PSBoundParameters.ContainsKey('Monitor'))
                {
                    $chosen = $monitors | Where-Object { $_.Index -eq $Monitor } | Select-Object -First 1
                    if(!$chosen)
                    {
                        throw "There is no monitor $Monitor. Monitors: $(($monitors | ForEach-Object { "$($_.Index) ($($_.Name))" }) -join ', ')"
                    }
                    $chosen
                }else{
                    $primary = $monitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
                    $(if($primary){$primary}else{$monitors[0]})
                }
            }
            'Window' {
                $pattern = $(if([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Window)){$Window}else{"*$Window*"})
                $matched = @(Get-CaptureTarget -Window -Name $pattern)
                if($matched.Count -eq 0)
                {
                    throw "No window matches '$Window'. Get-CaptureTarget -Window lists them"
                }
                if($matched.Count -gt 1)
                {
                    $list = ($matched | Select-Object -First 5 | ForEach-Object { "'$($_.Title)' ($($_.ProcessName))" }) -join ', '
                    throw "$($matched.Count) windows match '$Window': $list. Be more specific, or pipe one from Get-CaptureTarget -Window"
                }
                $matched[0]
            }
            'CurrentTerminal' { Get-CaptureTarget -CurrentTerminal }
            'Rectangle' {
                $regionX, $regionY, $regionWidth, $regionHeight = $Rectangle
                #Most encoders need even dimensions, so round down rather than fail
                $regionWidth = $regionWidth - ($regionWidth % 2)
                $regionHeight = $regionHeight - ($regionHeight % 2)
                if($regionWidth -lt 2 -or $regionHeight -lt 2)
                {
                    throw 'The rectangle must be at least 2 pixels wide and high'
                }
                #The monitor it fits inside, if any. macOS doesn't report screen sizes, so it's taken to be on the main screen
                $containing = $(if($IsMacOS){
                    $monitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
                }else{
                    $monitors | Where-Object {
                        $null -ne $_.Width -and $regionX -ge $_.X -and $regionY -ge $_.Y -and ($regionX + $regionWidth) -le ($_.X + $_.Width) -and ($regionY + $regionHeight) -le ($_.Y + $_.Height)
                    } | Select-Object -First 1
                })
                $regionSplat = @{
                    Kind = 'Region'
                    Name = "$($regionWidth)x$($regionHeight) at $regionX,$regionY"
                    X = $regionX
                    Y = $regionY
                    Width = $regionWidth
                    Height = $regionHeight
                    Monitor = $containing
                }
                New-CaptureTarget @regionSplat
            }
            'Target' { $Target }
            'Synthetic' {
                New-CaptureTarget -Kind Synthetic -Name 'Test pattern' -X 0 -Y 0 -Width $syntheticSize.Width -Height $syntheticSize.Height
            }
        }
        if($captureTarget.IsMinimized)
        {
            throw "The window '$($captureTarget.Name)' is minimized, so there's nothing to record. Restore it first"
        }
        write-verbose "Recording: $($captureTarget.Kind) $($captureTarget.Name)"

        $installation = Find-FFmpeg -IncludeCapability
        $backendSplat = @{
            Target = $captureTarget
            AvailableSources = $installation.CaptureSources
            Requested = $(if($PSCmdlet.ParameterSetName -eq 'Synthetic'){'Auto'}else{$Backend})
            MonitorCount = [math]::Max(1, $monitors.Count)
        }
        $chosenBackend = Select-CaptureBackend @backendSplat
        if($chosenBackend -eq 'gdigrab' -and $captureTarget.Kind -eq 'Window')
        {
            Write-Warning 'This ffmpeg build cannot capture a single window, so the window''s area of the screen is recorded, including anything that covers it. ffmpeg 8.1 or later records just the window'
        }

        if($VideoEncoder)
        {
            $encoderChoice = [PSCustomObject]@{ Codec = $Codec; Quality = 'Custom'; Family = 'Custom'; Encoder = $VideoEncoder; Arguments = [string[]]@(); PixelFormat = 'yuv420p' }
        }else{
            $encoderChoice = Select-VideoEncoder -Codec $Codec -Encoder $Encoder -Quality $Quality -WorkingEncoders $installation.Encoders -Fps $Fps
        }
        $captureInput = Get-CaptureInputArgument -Target $captureTarget -Backend $chosenBackend -Fps $Fps -ShowCursor (!$HideCursor)

        write-verbose 'Working out where to save'
        $startTime = [datetime]::Now
        $defaultExtension = $(if($Quality -eq 'Lossless'){'.mkv'}else{'.mp4'})
        if(!$Path)
        {
            $finalPath = Get-DefaultRecordingPath -Extension $defaultExtension -StartTime $startTime
        }elseif(Test-Path -LiteralPath $Path -PathType Container){
            $finalPath = Join-Path -Path (Get-Item -LiteralPath $Path).FullName -ChildPath ([System.IO.Path]::GetFileName((Get-DefaultRecordingPath -Extension $defaultExtension -StartTime $startTime)))
        }else{
            $finalPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        }
        $extension = [System.IO.Path]::GetExtension($finalPath).ToLowerInvariant()
        if($extension -notin '.mp4','.mkv','.mov')
        {
            throw "Recordings can be saved as .mp4, .mkv or .mov, not '$extension'"
        }
        $finalFolder = Split-Path -Path $finalPath -Parent
        if(!(Test-Path -LiteralPath $finalFolder -PathType Container))
        {
            throw "The folder to save in does not exist: $finalFolder"
        }
        if((Test-Path -LiteralPath $finalPath) -and !$Force)
        {
            throw "$finalPath already exists. Use -Force to overwrite it"
        }
        if($Quality -eq 'Lossless' -and $extension -ne '.mkv')
        {
            Write-Warning 'Lossless recordings are RGB, which most players can''t play. They convert well with ConvertTo-Gif, or re-encode them to share'
        }
        $recordingPath = Join-Path -Path $finalFolder -ChildPath "$([System.IO.Path]::GetFileNameWithoutExtension($finalPath)).recording.mkv"
        $progressPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "psScreenRecorder-$([guid]::NewGuid().ToString('N')).progress"

        $videoFilter = (@($captureInput.Filters) + @("fps=$Fps",'crop=trunc(iw/2)*2:trunc(ih/2)*2',"format=$($encoderChoice.PixelFormat)")) -join ','
        $ffmpegArguments = [System.Collections.Generic.List[string]]::new()
        $ffmpegArguments.AddRange([string[]]@('-hide_banner','-loglevel','error','-nostats','-progress',"file:$progressPath",'-stats_period','0.5','-y'))
        if($FFmpegInputArgument)
        {
            $ffmpegArguments.AddRange($FFmpegInputArgument)
        }
        $ffmpegArguments.AddRange($captureInput.InputArguments)
        $ffmpegArguments.AddRange([string[]]@('-vf',$videoFilter,'-c:v',$encoderChoice.Encoder))
        $ffmpegArguments.AddRange($encoderChoice.Arguments)
        if($PSBoundParameters.ContainsKey('Duration'))
        {
            $ffmpegArguments.AddRange([string[]]@('-t',$Duration.TotalSeconds.ToString($culture)))
        }
        if($FFmpegOutputArgument)
        {
            $ffmpegArguments.AddRange($FFmpegOutputArgument)
        }
        #If ffmpeg is killed, only what has reached the disk survives. Matroska holds each cluster in memory until
        #it's complete (5 seconds by default), and file output is buffered on top of that, so a short recording
        #could be lost entirely. Closing clusters every second, and flushing every packet, keeps the loss to
        #about a second. Measured: killed 1.5 seconds in, 0 frames survived without these, 31 with them
        $ffmpegArguments.AddRange([string[]]@('-cluster_time_limit','1000','-flush_packets','1','-f','matroska',$recordingPath))

        if(!$PSCmdlet.ShouldProcess($finalPath, "Record $($captureTarget.Kind.ToLower()) '$($captureTarget.Name)' with $chosenBackend and $($encoderChoice.Encoder)"))
        {
            return
        }

        if($StartOnFocusLoss)
        {
            Write-Host 'Switch to the window you want to show. Recording starts when this window loses focus.'
            $null = Wait-WindowFocus -WindowHandle $terminalHandle -Until Lost
            if(!$PSBoundParameters.ContainsKey('Delay'))
            {
                $Delay = $defaultFocusDelay
            }
        }
        if($Delay -gt [timespan]::Zero)
        {
            $delayEnd = [datetime]::Now + $Delay
            while([datetime]::Now -lt $delayEnd)
            {
                $remaining = $delayEnd - [datetime]::Now
                Write-Progress -Activity 'Recording starts in' -Status "$([math]::Ceiling($remaining.TotalSeconds)) seconds" -SecondsRemaining ([math]::Ceiling($remaining.TotalSeconds))
                Start-Sleep -Milliseconds ([math]::Min(250, [math]::Max(1, $remaining.TotalMilliseconds)))
            }
            Write-Progress -Activity 'Recording starts in' -Completed
        }

        $handle = Start-FFmpegProcess -FFmpegPath $installation.FFmpegPath -ArgumentList $ffmpegArguments -Confirm:$false
        if(!$script:psScreenRecorderNextId)
        {
            $script:psScreenRecorderNextId = 1
        }
        $recording = [PSCustomObject]@{
            PSTypeName = 'psScreenRecorder.Recording'
            Id = $script:psScreenRecorderNextId
            State = 'Recording'
            TargetName = $captureTarget.Name
            Elapsed = $null
            Frames = $null
            DroppedFrames = $null
            DuplicatedFrames = $null
            Size = $null
            Speed = $null
            Path = $finalPath
            RecordingPath = $recordingPath
            ProgressPath = $progressPath
            Target = $captureTarget
            Backend = $chosenBackend
            Encoder = $encoderChoice.Encoder
            Codec = $encoderChoice.Codec
            Quality = $encoderChoice.Quality
            Fps = $Fps
            Duration = $(if($PSBoundParameters.ContainsKey('Duration')){$Duration})
            StartTime = $handle.StartTime
            EndTime = $null
            ProcessId = $handle.ProcessId
            Arguments = $ffmpegArguments.ToArray()
            Error = $null
            Handle = $handle
        }
        $recording | Add-Member -MemberType MemberSet -Name PSStandardMembers -Value ([System.Management.Automation.PSMemberInfo[]]@($displayProperties))
        $script:psScreenRecorderNextId++
        $script:psScreenRecorderRecordings.Add($recording)
        Register-ScreenRecorderExitHandler -Recordings $script:psScreenRecorderRecordings

        #Catch the common failures, such as a capture source that can't open, now rather than at Stop
        $startupDeadline = [datetime]::Now + $startupWait
        while(!$handle.Process.HasExited -and [datetime]::Now -lt $startupDeadline -and !(Read-FFmpegProgress -Path $progressPath))
        {
            Start-Sleep -Milliseconds 100
        }
        if($handle.Process.HasExited -and $handle.Process.ExitCode -ne 0)
        {
            $exitInfo = Stop-FFmpegProcess -Handle $handle -Confirm:$false
            $null = Complete-ScreenRecording -Recording $recording -ExitInfo $exitInfo -ErrorAction SilentlyContinue
            throw "The recording could not start. $($recording.Error)"
        }

        if(!$blocking)
        {
            return $recording
        }

        $waitMode = $(if($StopOnFocusReturn){'FocusReturn'}elseif($PSBoundParameters.ContainsKey('Duration')){'Exit'}else{'Key'})
        $stopped = $false
        try{
            $reason = Wait-ScreenRecordingStop -Recording $recording -Mode $waitMode -WindowHandle $terminalHandle
            write-verbose "Stopping: $reason"
            $stopped = $true
            Stop-ScreenRecording -Recording $recording -Confirm:$false
        }finally{
            #Ctrl+C lands here, so stop and save rather than leave ffmpeg running
            if(!$stopped)
            {
                $null = Stop-ScreenRecording -Recording $recording -Confirm:$false
            }
        }
    }
}
