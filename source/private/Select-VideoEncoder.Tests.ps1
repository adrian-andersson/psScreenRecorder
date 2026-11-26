[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Select-VideoEncoder'
    . $fileName

    #As on the RTX 3090 dev machine: NVENC for H.264 and HEVC but not AV1, plus Media Foundation and software
    $rtx3090 = @('libx264','libx264rgb','libx265','libsvtav1','libaom-av1','h264_nvenc','hevc_nvenc','h264_mf')
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Select-VideoEncoder' {
    Context 'Auto' {
        It 'Prefers hardware for <Codec>, falling back to software where the GPU can''t' -ForEach @(
            @{ Codec = 'H264'; Expected = 'h264_nvenc' }
            @{ Codec = 'HEVC'; Expected = 'hevc_nvenc' }
            @{ Codec = 'AV1'; Expected = 'libsvtav1' }
        ) {
            (Select-VideoEncoder -Codec $Codec -WorkingEncoders $rtx3090).Encoder | Should -Be $Expected
        }

        It 'Tries hardware in order: NVENC, QSV, AMF, VideoToolbox, Media Foundation' {
            (Select-VideoEncoder -WorkingEncoders 'libx264','h264_mf','h264_amf','h264_qsv').Encoder | Should -Be 'h264_qsv'
            (Select-VideoEncoder -WorkingEncoders 'libx264','h264_mf','h264_videotoolbox').Encoder | Should -Be 'h264_videotoolbox'
            (Select-VideoEncoder -WorkingEncoders 'libx264','h264_mf').Encoder | Should -Be 'h264_mf'
        }

        It 'Uses libaom-av1 when SVT-AV1 is not there' {
            (Select-VideoEncoder -Codec AV1 -WorkingEncoders 'libaom-av1').Encoder | Should -Be 'libaom-av1'
        }

        It 'Throws, listing what works, when nothing can encode the codec' {
            { Select-VideoEncoder -Codec AV1 -WorkingEncoders 'libx264','h264_nvenc' } | Should -Throw '*No working AV1 encoder*libx264, h264_nvenc*'
        }
    }

    Context 'Asking for an encoder' {
        It 'Uses software when asked, even with hardware available' {
            (Select-VideoEncoder -Encoder Software -WorkingEncoders $rtx3090).Encoder | Should -Be 'libx264'
        }

        It 'Throws when the asked-for encoder does not work here' {
            { Select-VideoEncoder -Codec AV1 -Encoder Nvenc -WorkingEncoders $rtx3090 } | Should -Throw '*Nvenc AV1 encoder (av1_nvenc) does not work*'
        }

        It 'Throws when the family has no encoder for the codec' {
            { Select-VideoEncoder -Codec AV1 -Encoder MediaFoundation -WorkingEncoders $rtx3090 } | Should -Throw '*MediaFoundation has no AV1 encoder*'
        }
    }

    Context 'Settings' {
        It 'Uses <Expected> for <Encoder> at High quality' -ForEach @(
            @{ Encoder = 'libx264'; Expected = '-preset veryfast -crf 18 -g 60' }
            @{ Encoder = 'h264_nvenc'; Expected = '-preset p4 -rc vbr -cq 19 -b:v 0 -g 60' }
            @{ Encoder = 'h264_qsv'; Expected = '-preset faster -global_quality 20 -g 60' }
            @{ Encoder = 'h264_amf'; Expected = '-quality speed -rc cqp -qp_i 20 -qp_p 20 -g 60' }
            @{ Encoder = 'h264_mf'; Expected = '-rate_control quality -quality 80 -g 60' }
            @{ Encoder = 'h264_videotoolbox'; Expected = '-q:v 70 -realtime 1 -g 60' }
        ) {
            ((Select-VideoEncoder -WorkingEncoders $Encoder -Fps 30).Arguments -join ' ') | Should -Be $Expected
        }

        It 'Uses a lower quality setting for Standard' {
            ((Select-VideoEncoder -Encoder Software -Quality Standard -WorkingEncoders 'libx264').Arguments -join ' ') | Should -BeLike '*-crf 23*'
            ((Select-VideoEncoder -Codec HEVC -Encoder Software -Quality Standard -WorkingEncoders 'libx265').Arguments -join ' ') | Should -BeLike '*-crf 26*'
            ((Select-VideoEncoder -Codec AV1 -Quality Standard -WorkingEncoders 'libsvtav1').Arguments -join ' ') | Should -BeLike '*-crf 38*'
        }

        It 'Puts a keyframe every two seconds' {
            (Select-VideoEncoder -WorkingEncoders 'libx264' -Fps 25).Arguments[-1] | Should -Be '50'
        }

        It 'Uses yuv420p for software and NVENC, and nv12 for other hardware' {
            (Select-VideoEncoder -WorkingEncoders 'libx264').PixelFormat | Should -Be 'yuv420p'
            (Select-VideoEncoder -WorkingEncoders 'h264_nvenc').PixelFormat | Should -Be 'yuv420p'
            (Select-VideoEncoder -WorkingEncoders 'h264_qsv').PixelFormat | Should -Be 'nv12'
            (Select-VideoEncoder -WorkingEncoders 'h264_mf').PixelFormat | Should -Be 'nv12'
        }
    }

    Context 'Lossless' {
        It 'Uses libx264rgb at CRF 0 in RGB' {
            $choice = Select-VideoEncoder -Quality Lossless -WorkingEncoders $rtx3090
            $choice.Encoder | Should -Be 'libx264rgb'
            $choice.Arguments -join ' ' | Should -BeLike '-preset ultrafast -crf 0*'
            $choice.PixelFormat | Should -Be 'gbrp'
        }

        It 'Throws for <Case>' -ForEach @(
            @{ Case = 'another codec'; Splat = @{ Codec = 'HEVC' }; Message = '*isn''t available for HEVC*' }
            @{ Case = 'a hardware encoder'; Splat = @{ Encoder = 'Nvenc' }; Message = '*not Nvenc*' }
        ) {
            { Select-VideoEncoder -Quality Lossless -WorkingEncoders $rtx3090 @Splat } | Should -Throw $Message
        }

        It 'Throws without libx264rgb' {
            { Select-VideoEncoder -Quality Lossless -WorkingEncoders 'libx264' } | Should -Throw '*needs libx264rgb*'
        }
    }
}
