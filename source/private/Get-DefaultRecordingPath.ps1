function Get-DefaultRecordingPath
{
    <#
        .SYNOPSIS
            Work out where a recording is saved when no -Path is given

        .DESCRIPTION
            Saves in your Videos folder, named after the time it started, as Windows and macOS do with their own
            screen recordings:
                Videos/Screen Recording 2026-11-27 14-05-09.mp4

            Uses [Environment]::GetFolderPath('MyVideos'), which follows the platform's own setting (on Linux,
            XDG_VIDEOS_DIR). If that's empty, uses ~/Videos. The folder is created if it doesn't exist.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Get-DefaultRecordingPath -Extension '.mkv'

            #### DESCRIPTION
            Returns something like C:\Users\me\Videos\Screen Recording 2026-11-27 14-05-09.mkv
    #>

    [CmdletBinding()]
    [OutputType([string])]
    PARAM(
        #File extension, with the dot
        [Parameter()]
        [ValidateSet('.mp4','.mkv','.mov')]
        [string]$Extension = '.mp4',
        #The time to name the file after
        [Parameter()]
        [datetime]$StartTime = [datetime]::Now
    )
    process{
        $folder = [Environment]::GetFolderPath('MyVideos')
        if(!$folder)
        {
            $folder = Join-Path -Path $HOME -ChildPath 'Videos'
        }
        if(!(Test-Path -LiteralPath $folder -PathType Container))
        {
            $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop
        }
        Join-Path -Path $folder -ChildPath "Screen Recording $($StartTime.ToString('yyyy-MM-dd HH-mm-ss', [cultureinfo]::InvariantCulture))$Extension"
    }
}
