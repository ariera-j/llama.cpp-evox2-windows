@{
    # Copy to local.huihui-iq4xs-ple16.psd1 (ignored by Git) and edit.
    # Paths below are placeholders; this example contains no private input paths.
    # For the 128k-paper plan, set Inputs.'128k' in the private copy.

    RepoRoot = ''
    LogRoot = ''
    UmaLabel = '96GB'

    Builds = @{
        R5Common001Vulkan = @{
            BinDir = 'C:\path\to\llama.cpp-evox2-windows-r5\build-vulkan-common001\bin\Release'
            ExpectedBackend = 'Vulkan'
        }
        R5Common001ROCm = @{
            BinDir = 'C:\path\to\llama.cpp-evox2-windows-r5\build-rocm-common001\bin\Release'
            ExpectedBackend = 'ROCm'
        }
    }

    Models = @{
        HuihuiIQ4XSPle16 = @{
            Path = 'C:\path\to\Qwen3.8-Flash-Next-UD-IQ4_XS-ple16.gguf'
            Alias = 'huihui-unsloth-ud-iq4-xs-ple16'
        }
    }

    Inputs = @{
        '128k' = 'C:\path\to\nlp-survey-ch3-d15-b1.txt'
    }
}
