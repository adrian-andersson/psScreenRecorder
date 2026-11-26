function Resolve-FFmpegExecutable
{
    <#
        .SYNOPSIS
            Turn a file or folder path into the full path of an ffmpeg or ffprobe executable

        .DESCRIPTION
            Given a file, returns its full path if it exists. Given a folder, looks in it for the named tool,
            adding .exe on Windows. Returns nothing if neither is there.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Resolve-FFmpegExecutable -Path 'C:\Tools\ffmpeg\bin' -Name 'ffprobe'

            #### DESCRIPTION
            Returns C:\Tools\ffmpeg\bin\ffprobe.exe, if it exists.
    #>

    [CmdletBinding()]
    [OutputType([string])]
    PARAM(
        #Path to the executable, or to the folder that contains it
        [Parameter(Mandatory)]
        [string]$Path,
        #Tool to look for when Path is a folder
        [Parameter()]
        [ValidateSet('ffmpeg','ffprobe')]
        [string]$Name = 'ffmpeg'
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"
        $fileName = $(if($IsWindows){"$Name.exe"}else{$Name})
    }
    process{
        if(Test-Path -LiteralPath $Path -PathType Container)
        {
            $candidate = Join-Path -Path $Path -ChildPath $fileName
            write-verbose "Path is a folder, checking for: $candidate"
            if(Test-Path -LiteralPath $candidate -PathType Leaf)
            {
                (Get-Item -LiteralPath $candidate).FullName
            }
        }elseif(Test-Path -LiteralPath $Path -PathType Leaf){
            write-verbose 'Path is a file'
            (Get-Item -LiteralPath $Path).FullName
        }else{
            write-verbose "Nothing found at: $Path"
        }
    }
}
