function Add-VideoMetadataMember
{
    <#
        .SYNOPSIS
            Add a video's duration, size, frame rate and codec to its file object

        .DESCRIPTION
            Reads the file with Get-VideoMetadata and adds Duration, Width, Height, FrameRate and VideoCodec as
            properties, so a saved recording shows its details and still pipes as a file. If the details can't
            be read, the file is returned as it is.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Get-Item .\demo.mp4 | Add-VideoMetadataMember

            #### DESCRIPTION
            Returns demo.mp4 with its video details added.
    #>

    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    PARAM(
        #The video file
        [Parameter(Mandatory,ValueFromPipeline)]
        [System.IO.FileInfo]$File
    )
    process{
        try{
            $metadata = Get-VideoMetadata -Path $File.FullName -ErrorAction Stop
            foreach($property in 'Duration','Width','Height','FrameRate','VideoCodec')
            {
                $File | Add-Member -NotePropertyName $property -NotePropertyValue $metadata.$property -Force
            }
        }catch{
            write-verbose "Unable to read the details of $($File.FullName): $($_.Exception.Message)"
        }
        $File
    }
}
