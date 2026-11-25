@{
    LogRoot = 'C:\path\to\evox2-logs'

    # BinDir contains llama-bench.exe, llama-cli.exe and evox2-build.json.
    Builds = @{
        VulkanStage2 = @{
            BinDir = 'C:\path\to\stage2-vulkan\bin\Release'
            ExpectedBackend = 'Vulkan'
        }
        VulkanCommon001 = @{
            BinDir = 'C:\path\to\common001-vulkan\bin\Release'
            ExpectedBackend = 'Vulkan'
        }
        RocmCommon001 = @{
            BinDir = 'C:\path\to\common001-rocm\bin\Release'
            ExpectedBackend = 'ROCm'
        }
    }

    Models = @{
        UnslothPle16 = @{
            Alias = 'unsloth-ple16'
            Path = 'C:\path\to\IQ3-PLE16.gguf'
        }
        AgentionRocmFp4FastPle16 = @{
            Alias = 'agention-rocmfp4-fast-v2-ple16'
            Path = 'C:\path\to\ROCmFP4-FAST-PLE16.gguf'
        }
    }

    Inputs = @{
        '64k' = 'C:\path\to\nlp-survey-ch3-d7-b1.txt'
    }
}
