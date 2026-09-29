@{
    SchemaVersion = 1
    Name = 'qwen38-baseline'

    Settings = @{
        # Pause between independent child processes so the driver/runtime has
        # time to release allocations.
        CooldownSeconds = 10

        # Keep later measurements even if one child run fails.
        ContinueOnError = $true
    }

    Defaults = @{
        CliParameters = @{
            KvType           = 'f16'
            UBatch           = 1024
            Batch            = 2048
            Threads          = 4
            GpuLayers        = 999
            CpuMoe           = 0
            FlashAttn        = '1'
            GenerationTokens = 1024
            PromptCacheMiB   = 0
            Temperature      = 0.2
            TopP             = 0.8
            Reasoning        = 'off'
            Fit              = 'off'
            ResourceMonitor  = $true
        }

        BenchParameters = @{
            KvType          = 'f16'
            UBatch          = 1024
            Batch           = 2048
            Threads         = 4
            GpuLayers       = 999
            CpuMoe          = 0
            FlashAttn       = 'on'
            Repetitions     = 3
            ResourceMonitor = $true
        }
    }

    Jobs = @(
        # Real Japanese input baseline. The Context/InputKey pair stays
        # together inside one Case, so the matrix cannot accidentally pair
        # a 64k context with the wrong input file.
        @{
            Name = 'cli-real-input'
            Tool = 'cli'

            BuildKeys = @(
                'R3Vulkan'
                'R3ROCm'
            )

            ModelKeys = @(
                'UnslothOriginal'
            )

            Cases = @(
                @{
                    Name = '64k'
                    Parameters = @{
                        Context  = 65536
                        InputKey = '64k'
                    }
                }
            )

            Variants = @(
                @{
                    Name = 'nomtp'
                    Parameters = @{}
                }
            )
        }

        # Small synthetic llama-bench anchor for public reproducibility.
        # -p and -n are separate tests in llama-bench.
        @{
            Name = 'bench-short'
            Tool = 'bench'

            BuildKeys = @(
                'R3Vulkan'
                'R3ROCm'
            )

            ModelKeys = @(
                'UnslothOriginal'
            )

            Cases = @(
                @{
                    Name = 'pp512-tg128'
                    Parameters = @{
                        PromptTokens     = @(512)
                        GenerationTokens = @(128)
                        Depths           = @(0)
                    }
                }
            )
        }
    )
}
