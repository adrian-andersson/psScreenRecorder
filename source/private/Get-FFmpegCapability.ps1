function Get-FFmpegCapability
{
    <#
        .SYNOPSIS
            Work out which capture sources and video encoders an ffmpeg build can use on this machine

        .DESCRIPTION
            Reads ffmpeg's filter, device and encoder lists, then picks out:
              - CaptureSources: the screen capture sources psScreenRecorder knows how to drive
              - ListedEncoders: the video encoders psScreenRecorder can use that the build includes
              - WorkingEncoders: those of the listed encoders that pass a short test encode

            Listed is not the same as working. A build includes every hardware encoder it was compiled
            with, whatever GPU the machine has, so each one is tried with Test-FFmpegEncoder.

            That takes a couple of seconds, so the result is cached twice:
              - in memory, for the rest of the session
              - in ffmpeg-capability.json in the cache folder (see Get-ScreenRecorderCacheFolder), for later sessions

            The file is only used if a fingerprint still matches, checked without starting ffmpeg: the
            ffmpeg path, version, file size and modified time, the computer name, and the lists of sources
            and encoders this version of the module knows about. It is also ignored once it is older than
            MaxCacheAge, as a GPU driver update can change which encoders work. -Refresh ignores both caches.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            $ffmpeg = Find-FFmpeg
            Get-FFmpegCapability -FFmpegPath $ffmpeg.FFmpegPath -Version $ffmpeg.Version

            #### DESCRIPTION
            Show what the current ffmpeg can capture with and encode to.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    PARAM(
        #Full path to ffmpeg
        [Parameter(Mandatory)]
        [string]$FFmpegPath,
        #ffmpeg's version, as Find-FFmpeg reports it. Part of the cache fingerprint
        [Parameter(Mandatory)]
        [string]$Version,
        #Check again, ignoring the memory and file caches
        [Parameter()]
        [switch]$Refresh,
        #How old the cache file can get before it is checked again
        [Parameter()]
        [timespan]$MaxCacheAge = [timespan]::FromDays(30)
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"

        #Screen capture sources, in order of preference within each platform
        $knownCaptureSources = @('gfxcapture','ddagrab','gdigrab','avfoundation','x11grab','kmsgrab')
        #Video encoders worth testing. VAAPI and V4L2 need device setup a plain test encode can't do, so they are left out for now
        $knownEncoders = @(
            'libx264','libx264rgb','libx265','libsvtav1','libaom-av1'
            'h264_nvenc','hevc_nvenc','av1_nvenc'
            'h264_qsv','hevc_qsv','av1_qsv'
            'h264_amf','hevc_amf','av1_amf'
            'h264_mf','hevc_mf'
            'h264_videotoolbox','hevc_videotoolbox'
        )
        $cacheFileName = 'ffmpeg-capability.json'
        if(!$script:psScreenRecorderCapability)
        {
            $script:psScreenRecorderCapability = @{}
        }
    }
    process{
        if(!$Refresh -and $script:psScreenRecorderCapability.ContainsKey($FFmpegPath))
        {
            write-verbose 'Using capabilities cached in memory'
            return $script:psScreenRecorderCapability[$FFmpegPath]
        }

        $ffmpegFile = Get-Item -LiteralPath $FFmpegPath -ErrorAction Stop
        $fingerprint = [ordered]@{
            FFmpegPath = $ffmpegFile.FullName
            Version = $Version
            Length = $ffmpegFile.Length
            LastWriteTimeUtc = $ffmpegFile.LastWriteTimeUtc.ToString('o')
            ComputerName = [Environment]::MachineName
            KnownCaptureSources = $knownCaptureSources -join ','
            KnownEncoders = $knownEncoders -join ','
        }
        $cacheFolder = Get-ScreenRecorderCacheFolder
        $cacheFile = Join-Path -Path $cacheFolder -ChildPath $cacheFileName

        if(!$Refresh -and (Test-Path -LiteralPath $cacheFile -PathType Leaf))
        {
            write-verbose "Checking the cache file: $cacheFile"
            try{
                $cached = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop | ConvertFrom-Json -DateKind String -ErrorAction Stop
                $matchingEntry = @($cached.Entries).Where{
                    $entry = $_
                    @($fingerprint.Keys).Where{ [string]$entry.Fingerprint.$_ -cne [string]$fingerprint[$_] }.Count -eq 0
                } | Select-Object -First 1
                if($matchingEntry)
                {
                    $checkedAt = [datetime]::Parse($matchingEntry.CheckedAtUtc, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                    if(([datetime]::UtcNow - $checkedAt) -le $MaxCacheAge)
                    {
                        write-verbose "Cache file matches, checked at $($checkedAt.ToString('o'))"
                        $capability = [PSCustomObject]@{
                            PSTypeName = 'psScreenRecorder.FFmpegCapability'
                            FFmpegPath = $FFmpegPath
                            CaptureSources = [string[]]@($matchingEntry.CaptureSources)
                            ListedEncoders = [string[]]@($matchingEntry.ListedEncoders)
                            WorkingEncoders = [string[]]@($matchingEntry.WorkingEncoders)
                            CheckedAt = $checkedAt
                            FromCache = $true
                        }
                        $script:psScreenRecorderCapability[$FFmpegPath] = $capability
                        return $capability
                    }
                    write-verbose "Cache file entry is older than $MaxCacheAge, checking again"
                }else{
                    write-verbose 'Nothing in the cache file matches this ffmpeg, checking again'
                }
            }catch{
                write-verbose "Unable to read the cache file, checking again: $($_.Exception.Message)"
            }
        }

        write-verbose 'Reading filters, devices and encoders'
        $filterLines = (Invoke-FFmpeg -ExecutablePath $FFmpegPath -ArgumentList '-hide_banner','-filters').StandardOutput
        $deviceLines = (Invoke-FFmpeg -ExecutablePath $FFmpegPath -ArgumentList '-hide_banner','-devices').StandardOutput
        $encoderLines = (Invoke-FFmpeg -ExecutablePath $FFmpegPath -ArgumentList '-hide_banner','-encoders').StandardOutput

        #Filter lines look like ' .. ddagrab           |->V       Grab Windows Desktop images...'. Older builds have three flag characters
        $filterNames = foreach($line in $filterLines)
        {
            if($line -match '^\s*[A-Z\.]{2,3}\s+(?<name>\S+)\s+\S*->\S*\s')
            {
                $Matches.name
            }
        }
        #Device lines look like ' D  gdigrab         GDI API...'. D means it can be read from, which is what capture needs
        $deviceNames = foreach($line in $deviceLines)
        {
            if($line -match '^\s(?<flags>[D ][E ])\s+(?<name>\S+)\s' -and $Matches.flags.Contains('D'))
            {
                $Matches.name -split ','
            }
        }
        #Encoder lines look like ' V....D libx264    libx264 H.264...'. The legend line ' V..... = Video' is skipped
        $encoderNames = foreach($line in $encoderLines)
        {
            if($line -match '^\s*V[A-Z\.]{5}\s+(?<name>\S+)\s' -and $Matches.name -ne '=')
            {
                $Matches.name
            }
        }

        $captureSources = [string[]]@($knownCaptureSources.Where{ $_ -in $filterNames -or $_ -in $deviceNames })
        $listedEncoders = [string[]]@($knownEncoders.Where{ $_ -in $encoderNames })
        write-verbose "Capture sources: $($captureSources -join ', ')"
        write-verbose "Listed encoders: $($listedEncoders -join ', ')"

        $workingEncoders = [string[]]@(
            foreach($encoder in $listedEncoders)
            {
                if(Test-FFmpegEncoder -FFmpegPath $FFmpegPath -Encoder $encoder)
                {
                    $encoder
                }
            }
        )
        write-verbose "Working encoders: $($workingEncoders -join ', ')"
        $checkedAt = [datetime]::UtcNow

        $capability = [PSCustomObject]@{
            PSTypeName = 'psScreenRecorder.FFmpegCapability'
            FFmpegPath = $FFmpegPath
            CaptureSources = $captureSources
            ListedEncoders = $listedEncoders
            WorkingEncoders = $workingEncoders
            CheckedAt = $checkedAt
            FromCache = $false
        }
        $script:psScreenRecorderCapability[$FFmpegPath] = $capability

        write-verbose "Saving to the cache file: $cacheFile"
        try{
            #Keep entries for other ffmpeg installs, so switching between them doesn't re-check each time
            $otherEntries = @()
            if(Test-Path -LiteralPath $cacheFile -PathType Leaf)
            {
                try{
                    $existing = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop | ConvertFrom-Json -DateKind String -ErrorAction Stop
                    $otherEntries = @(@($existing.Entries).Where{ $_.Fingerprint.FFmpegPath -ne $fingerprint.FFmpegPath -or $_.Fingerprint.ComputerName -ne $fingerprint.ComputerName })
                }catch{
                    write-verbose 'Existing cache file is unreadable, replacing it'
                }
            }
            $newEntry = [ordered]@{
                Fingerprint = $fingerprint
                CheckedAtUtc = $checkedAt.ToString('o')
                CaptureSources = $captureSources
                ListedEncoders = $listedEncoders
                WorkingEncoders = $workingEncoders
            }
            $cacheContent = [ordered]@{
                Description = 'psScreenRecorder cache of what ffmpeg can do on this machine. Safe to delete'
                Entries = @($otherEntries) + @($newEntry)
            }
            if(!(Test-Path -LiteralPath $cacheFolder -PathType Container))
            {
                $null = New-Item -ItemType Directory -Path $cacheFolder -Force -ErrorAction Stop
            }
            #Write to a temporary file and move it into place, so a session reading at the same time never sees half a file
            $temporaryFile = "$cacheFile.$([guid]::NewGuid().ToString('N')).tmp"
            ConvertTo-Json -InputObject $cacheContent -Depth 5 | Set-Content -LiteralPath $temporaryFile -Encoding utf8NoBOM -ErrorAction Stop
            Move-Item -LiteralPath $temporaryFile -Destination $cacheFile -Force -ErrorAction Stop
        }catch{
            Write-Warning "Unable to save ffmpeg capabilities to $($cacheFile): $($_.Exception.Message)"
        }

        $capability
    }
}
