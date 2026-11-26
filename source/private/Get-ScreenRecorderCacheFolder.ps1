function Get-ScreenRecorderCacheFolder
{
    <#
        .SYNOPSIS
            Get the folder psScreenRecorder keeps its cache files in

        .DESCRIPTION
            The cache holds results that are slow to work out and safe to throw away, such as which
            encoders work on this machine. Deleting the folder only means they are worked out again.

            Uses, in order:
              - $env:PSSCREENRECORDER_CACHE, if set. Tests and CI use this to stay out of the real cache
              - Windows: LocalApplicationData\psScreenRecorder. Local, not roaming, as results depend on the machine's hardware
              - macOS: ~/Library/Caches/psScreenRecorder
              - Linux: $XDG_CACHE_HOME/psScreenRecorder, or ~/.cache/psScreenRecorder

            The folder is not created here. Whatever writes to it creates it.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Get-ScreenRecorderCacheFolder

            #### DESCRIPTION
            Returns something like C:\Users\me\AppData\Local\psScreenRecorder on Windows.
    #>

    [CmdletBinding()]
    [OutputType([string])]
    PARAM()
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        $folderName = 'psScreenRecorder'
    }
    process{
        $override = [Environment]::GetEnvironmentVariable('PSSCREENRECORDER_CACHE')
        if($override)
        {
            write-verbose "Using PSSCREENRECORDER_CACHE: $override"
            return $override
        }
        if($IsWindows)
        {
            Join-Path -Path ([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath $folderName
        }elseif($IsMacOS){
            Join-Path -Path $HOME -ChildPath 'Library' -AdditionalChildPath 'Caches',$folderName
        }else{
            $xdgCache = [Environment]::GetEnvironmentVariable('XDG_CACHE_HOME')
            if(!$xdgCache)
            {
                $xdgCache = Join-Path -Path $HOME -ChildPath '.cache'
            }
            Join-Path -Path $xdgCache -ChildPath $folderName
        }
    }
}
