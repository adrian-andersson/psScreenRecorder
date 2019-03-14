function install-ffMpeg
{

    <#
        .SYNOPSIS
            Download ffmpeg
            
        .DESCRIPTION
            Download FFMPEG zip file
            Extract to allUsersProfile folder
            
        .PARAMETER ffmpegUri
            URI for where the zip file lives

        .PARAMETER tempPath
            Path to save the zip file

        .PARAMETER installPath
            Where to extract the zip file
            
        ------------
        .EXAMPLE
            install-ffMpeg
            
            
            
        .NOTES
            Author: Adrian Andersson
            
            
            Changelog:

                2019-03-14 - AA
                    - Initial Script
                    - Tested and working
                    
        .COMPONENT
            psScreenRecorder
    #>

    [CmdletBinding()]
    PARAM(
        [string]$ffmpegUri = 'https://ffmpeg.zeranoe.com/builds/win64/static/ffmpeg-20190312-d227ed5-win64-static.zip',
        [string]$tempPath = "$($env:temp)\ffmpeg.zip",
        [string]$installPath = "$($env:ALLUSERSPROFILE)\ffmpeg"

    )
    begin{
        #Return the script name when running verbose, makes it tidier
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        #Return the sent variables when running debug
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"
        
    }
    
    process{
        write-verbose 'Download ffmpeg'
        try{
            Invoke-WebRequest -Uri $ffmpegUri -OutFile $tempPath -ErrorAction Stop
        }catch{
            throw 'Unable to download ffmpeg'
        }

        write-verbose 'Checking for install folder'
        if(!(test-path $installPath))
        {
            try{
                new-item -ItemType Directory -Path $installPath -Force
            }catch{
                throw 'Unable to create installPath'
            }
            
        }
        
        write-verbose 'Uncompressing zip'
        try{
            Expand-Archive -Path $tempPath -DestinationPath $installPath -Force
        }catch{
            throw 'Unable to expand archive'
        }
       
        write-verbose 'Installation Complete'
    }
    end{
        if(test-path $tempPath)
        {
            write-verbose 'Removing zip file'
            try{
                remove-item $tempPath -Force
                write-verbose 'Zip file removed'
            }catch{
                write-warning 'Unable to remove the ffmpeg zip file'
            }
        }
        
    }
    
}