function Select-VideoEncoder
{
    <#
        .SYNOPSIS
            Choose the video encoder, its settings and pixel format for a recording

        .DESCRIPTION
            Picks an encoder for the codec, from those that passed a test encode on this machine, and the
            settings for the quality asked for.

            With -Encoder Auto, hardware is tried first, as it leaves the CPU free for whatever is being
            recorded: NVIDIA (NVENC), Intel (QSV), AMD (AMF), Apple (VideoToolbox), Windows Media Foundation,
            then software (x264, x265, SVT-AV1).

            Quality:
              High      visually lossless for screen content. The default
              Standard  smaller files, still clear text
              Lossless  every pixel exactly as captured, in RGB, using libx264rgb. The files are large, and
                        most players can't play them, so convert them with ConvertTo-Gif, or re-encode them,
                        afterwards. H.264 and software encoding only

            High and Standard use 4:2:0 pixel formats (yuv420p or nv12), which every player handles.
            Keyframes are every two seconds, so the result can be cut and seeked accurately.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Select-VideoEncoder -Codec HEVC -WorkingEncoders 'libx264','libx265','hevc_nvenc'

            #### DESCRIPTION
            Returns hevc_nvenc with High quality settings.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    PARAM(
        #Video codec
        [Parameter()]
        [ValidateSet('H264','HEVC','AV1')]
        [string]$Codec = 'H264',
        #Which encoder family to use. Auto prefers hardware
        [Parameter()]
        [ValidateSet('Auto','Software','Nvenc','Qsv','Amf','VideoToolbox','MediaFoundation')]
        [string]$Encoder = 'Auto',
        #Quality
        [Parameter()]
        [ValidateSet('High','Standard','Lossless')]
        [string]$Quality = 'High',
        #Encoders that work on this machine, from Find-FFmpeg -IncludeCapability
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$WorkingEncoders,
        #Frames per second, for the keyframe interval
        [Parameter()]
        [ValidateRange(1,240)]
        [int]$Fps = 30
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        #Hardware first, in the order Auto tries them
        $encoderNames = @{
            H264 = [ordered]@{ Nvenc = 'h264_nvenc'; Qsv = 'h264_qsv'; Amf = 'h264_amf'; VideoToolbox = 'h264_videotoolbox'; MediaFoundation = 'h264_mf'; Software = 'libx264' }
            HEVC = [ordered]@{ Nvenc = 'hevc_nvenc'; Qsv = 'hevc_qsv'; Amf = 'hevc_amf'; VideoToolbox = 'hevc_videotoolbox'; MediaFoundation = 'hevc_mf'; Software = 'libx265' }
            AV1 = [ordered]@{ Nvenc = 'av1_nvenc'; Qsv = 'av1_qsv'; Amf = 'av1_amf'; Software = 'libsvtav1' }
        }
        #Index 0 is High, 1 is Standard
        $settings = @{
            libx264 = { param($level) '-preset','veryfast','-crf',@('18','23')[$level] }
            libx265 = { param($level) '-preset','superfast','-crf',@('20','26')[$level] }
            libsvtav1 = { param($level) '-preset','10','-crf',@('30','38')[$level] }
            'libaom-av1' = { param($level) '-cpu-used','8','-row-mt','1','-crf',@('30','38')[$level] }
            Nvenc = { param($level) '-preset','p4','-rc','vbr','-cq',@('19','26')[$level],'-b:v','0' }
            Qsv = { param($level) '-preset','faster','-global_quality',@('20','27')[$level] }
            Amf = { param($level) '-quality','speed','-rc','cqp','-qp_i',@('20','26')[$level],'-qp_p',@('20','26')[$level] }
            MediaFoundation = { param($level) '-rate_control','quality','-quality',@('80','60')[$level] }
            VideoToolbox = { param($level) '-q:v',@('70','55')[$level],'-realtime','1' }
        }
        $keyframeArguments = @('-g',[string]($Fps * 2))
    }
    process{
        if($Quality -eq 'Lossless')
        {
            if($Codec -ne 'H264')
            {
                throw "Lossless recording uses H.264 (libx264rgb). It isn't available for $Codec"
            }
            if($Encoder -notin 'Auto','Software')
            {
                throw "Lossless recording uses software encoding (libx264rgb), not $Encoder"
            }
            if('libx264rgb' -notin $WorkingEncoders)
            {
                throw 'Lossless recording needs libx264rgb, which this ffmpeg build does not have'
            }
            return [PSCustomObject]@{
                PSTypeName = 'psScreenRecorder.EncoderChoice'
                Codec = $Codec
                Quality = $Quality
                Family = 'Software'
                Encoder = 'libx264rgb'
                Arguments = [string[]](@('-preset','ultrafast','-crf','0') + $keyframeArguments)
                #Planar RGB is what libx264rgb stores, so converting straight to it avoids a second conversion
                PixelFormat = 'gbrp'
            }
        }

        $familyNames = $encoderNames[$Codec]
        $families = $(if($Encoder -eq 'Auto'){@($familyNames.Keys)}else{@($Encoder)})
        $chosenFamily = $null
        $chosenEncoder = $null
        foreach($family in $families)
        {
            if(!$familyNames.Contains($family))
            {
                continue
            }
            $candidates = @($familyNames[$family])
            if($Codec -eq 'AV1' -and $family -eq 'Software')
            {
                $candidates = @('libsvtav1','libaom-av1')
            }
            $working = $candidates | Where-Object { $_ -in $WorkingEncoders } | Select-Object -First 1
            if($working)
            {
                $chosenFamily = $family
                $chosenEncoder = $working
                break
            }
        }

        if(!$chosenEncoder)
        {
            $available = $(if($WorkingEncoders){$WorkingEncoders -join ', '}else{'none'})
            if($Encoder -eq 'Auto')
            {
                throw "No working $Codec encoder was found. Encoders that work here: $available"
            }
            if(!$familyNames.Contains($Encoder))
            {
                throw "$Encoder has no $Codec encoder. Encoders that work here: $available"
            }
            throw "The $Encoder $Codec encoder ($($familyNames[$Encoder])) does not work on this machine. Encoders that work here: $available"
        }
        write-verbose "Chose $chosenEncoder ($chosenFamily)"

        $level = $(if($Quality -eq 'Standard'){1}else{0})
        $settingKey = $(if($chosenFamily -eq 'Software'){$chosenEncoder}else{$chosenFamily})
        $encoderArguments = [string[]](@(& $settings[$settingKey] $level) + $keyframeArguments)
        #NVENC and software encoders take yuv420p. The other hardware encoders want nv12, which is also 4:2:0
        $pixelFormat = $(if($chosenFamily -in 'Software','Nvenc'){'yuv420p'}else{'nv12'})

        [PSCustomObject]@{
            PSTypeName = 'psScreenRecorder.EncoderChoice'
            Codec = $Codec
            Quality = $Quality
            Family = $chosenFamily
            Encoder = $chosenEncoder
            Arguments = $encoderArguments
            PixelFormat = $pixelFormat
        }
    }
}
