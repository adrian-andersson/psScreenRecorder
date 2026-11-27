function Find-FFmpeg
{
    <#
        .SYNOPSIS
            Find the ffmpeg and ffprobe that psScreenRecorder will use

        .DESCRIPTION
            psScreenRecorder does not download, install or ship ffmpeg. ffmpeg builds are licensed under the
            LGPL or GPL depending on how they were built, and many include patent-encumbered encoders, so
            installing it is left to you and your package manager.

            Looks for ffmpeg in this order, and uses the first one found:
              1. The -Path parameter
              2. The PSSCREENRECORDER_FFMPEG environment variable
              3. ffmpeg on your PATH

            A path can be the ffmpeg executable, or the folder it is in. ffprobe is looked for in the same
            folder first, then on PATH.

            The result is cached for the session, so every other command uses the same ffmpeg. Giving -Path
            replaces the cached one. Use -Refresh to look again.

            If ffmpeg can't be found, this throws, with how to install it on your operating system.

            -IncludeCapability also reports which capture sources the build has, and which video encoders
            actually work on this machine. An encoder can be listed by ffmpeg and still fail, for example an
            NVIDIA encoder on a GPU that doesn't support that codec, so each one is tried with a short test
            encode. That takes a few seconds, so the result is saved to a cache file and reused until ffmpeg
            changes (a different path, version, size or modified time), the file is 30 days old, or you use
            -Refresh. The cache lives in your local app data or cache folder; set $env:PSSCREENRECORDER_CACHE
            to put it somewhere else.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Find-FFmpeg

            #### DESCRIPTION
            Find ffmpeg from the environment variable or PATH, and show its path and version.

        .EXAMPLE
            Find-FFmpeg -Path 'C:\Tools\ffmpeg\bin'

            #### DESCRIPTION
            Use the ffmpeg in a specific folder for the rest of the session.

        .EXAMPLE
            Find-FFmpeg -IncludeCapability | Select-Object -ExpandProperty Encoders

            #### DESCRIPTION
            List the video encoders that work on this machine.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    PARAM(
        #ffmpeg executable, or the folder that contains it
        [Parameter(Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        #Look again, instead of using the result cached for this session
        [Parameter()]
        [switch]$Refresh,
        #Also list the capture sources and working video encoders
        [Parameter()]
        [switch]$IncludeCapability
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"

        $environmentVariable = 'PSSCREENRECORDER_FFMPEG'
        $installHint = $(
            if($IsWindows){
                'winget install Gyan.FFmpeg (or get a build from https://ffmpeg.org/download.html)'
            }elseif($IsMacOS){
                'brew install ffmpeg'
            }else{
                'sudo apt install ffmpeg (or your distribution''s package manager)'
            }
        )
    }
    process{
        #The cached ffmpeg is only reused while it's still there. If it has been moved, removed or uninstalled
        #since, look again, rather than hand out a path that no longer works
        $cachedIsGone = $script:psScreenRecorderFFmpeg -and !(Test-Path -LiteralPath $script:psScreenRecorderFFmpeg.FFmpegPath -PathType Leaf)
        if($cachedIsGone)
        {
            write-verbose "The cached ffmpeg is no longer at $($script:psScreenRecorderFFmpeg.FFmpegPath), looking again"
            $script:psScreenRecorderFFmpeg = $null
        }
        if(!$Path -and !$Refresh -and $script:psScreenRecorderFFmpeg)
        {
            write-verbose "Using the cached ffmpeg: $($script:psScreenRecorderFFmpeg.FFmpegPath)"
            $installation = $script:psScreenRecorderFFmpeg
        }else{
            $source = $null
            $ffmpegPath = $null
            if($Path)
            {
                write-verbose "Checking the path given: $Path"
                $ffmpegPath = Resolve-FFmpegExecutable -Path $Path -Name 'ffmpeg'
                if(!$ffmpegPath)
                {
                    throw "ffmpeg was not found at: $Path"
                }
                $source = 'Parameter'
            }elseif([Environment]::GetEnvironmentVariable($environmentVariable)){
                $environmentPath = [Environment]::GetEnvironmentVariable($environmentVariable)
                write-verbose "Checking $($environmentVariable): $environmentPath"
                $ffmpegPath = Resolve-FFmpegExecutable -Path $environmentPath -Name 'ffmpeg'
                if(!$ffmpegPath)
                {
                    throw "ffmpeg was not found at the path in `$env:$($environmentVariable): $environmentPath"
                }
                $source = 'Environment'
            }else{
                write-verbose 'Checking PATH'
                $command = Get-Command -Name 'ffmpeg' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
                if($command)
                {
                    $ffmpegPath = $command.Source
                    $source = 'Path'
                }
            }

            if(!$ffmpegPath)
            {
                throw "ffmpeg was not found. psScreenRecorder does not install ffmpeg, as ffmpeg builds come with their own licence and patent obligations. Install it with: $installHint. Then put it on your PATH, set `$env:$environmentVariable to where it is, or run Find-FFmpeg -Path <path>."
            }
            write-verbose "Found ffmpeg: $ffmpegPath ($source)"

            write-verbose 'Checking it runs, and getting its version'
            try{
                $versionOutput = (Invoke-FFmpeg -ExecutablePath $ffmpegPath -ArgumentList '-hide_banner','-version' -ErrorAction Stop).StandardOutput
            }catch{
                throw "$ffmpegPath did not run as ffmpeg: $($_.Exception.Message)"
            }
            $firstLine = $versionOutput | Select-Object -First 1
            if($firstLine -notmatch '^ffmpeg version (?<version>\S+)')
            {
                throw "$ffmpegPath does not look like ffmpeg. It reported: $firstLine"
            }
            $versionString = $Matches.version
            write-verbose "Version: $versionString"

            #Release builds look like 9.1, 6.1.1-3ubuntu5 or n7.1. Builds from git (N-113000-g...) have no number
            $versionNumber = $null
            if($versionString -match '^n?(?<major>\d+)\.(?<minor>\d+)(\.(?<build>\d+))?')
            {
                $versionNumber = [version]::new([int]$Matches.major, [int]$Matches.minor, $(if($Matches.build){[int]$Matches.build}else{0}))
            }

            write-verbose 'Looking for ffprobe next to ffmpeg, then on PATH'
            $ffprobePath = Resolve-FFmpegExecutable -Path (Split-Path -Path $ffmpegPath -Parent) -Name 'ffprobe'
            if(!$ffprobePath)
            {
                $probeCommand = Get-Command -Name 'ffprobe' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
                $ffprobePath = $probeCommand.Source
            }
            if(!$ffprobePath)
            {
                Write-Warning 'ffprobe was not found. Commands that read video details, such as Get-VideoMetadata, will not work'
            }

            $installation = [PSCustomObject]@{
                PSTypeName = 'psScreenRecorder.FFmpegInstallation'
                FFmpegPath = $ffmpegPath
                FFprobePath = $ffprobePath
                Version = $versionString
                VersionNumber = $versionNumber
                Source = $source
            }
            $script:psScreenRecorderFFmpeg = $installation
        }

        if($IncludeCapability)
        {
            write-verbose 'Adding capabilities'
            $capability = Get-FFmpegCapability -FFmpegPath $installation.FFmpegPath -Version $installation.Version -Refresh:$Refresh
            [PSCustomObject]@{
                PSTypeName = 'psScreenRecorder.FFmpegInstallation'
                FFmpegPath = $installation.FFmpegPath
                FFprobePath = $installation.FFprobePath
                Version = $installation.Version
                VersionNumber = $installation.VersionNumber
                Source = $installation.Source
                CaptureSources = $capability.CaptureSources
                Encoders = $capability.WorkingEncoders
                CapabilityCheckedAt = $capability.CheckedAt
            }
        }else{
            $installation
        }
    }
}
