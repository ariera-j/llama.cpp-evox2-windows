@{
    SchemaVersion = 1
    Name = 'qwen38-longctx'

    Settings = @{
        CooldownSeconds = 10
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
        # Primary real-input long-context series.
        @{
            Name = 'cli-longctx'
            Tool = 'cli'

            # Add R3Vulkan here when a two-backend overnight run is desired.
            BuildKeys = @(
                'R3ROCm'
            )

            ModelKeys = @(
                'UnslothOriginal'
            )

            Cases = @(
                @{
                    Name = '32k'
                    Parameters = @{
                        Context  = 32768
                        InputKey = '32k'
                    }
                }
                @{
                    Name = '64k'
                    Parameters = @{
                        Context  = 65536
                        InputKey = '64k'
                    }
                }
                @{
                    Name = '96k'
                    Parameters = @{
                        Context  = 98304
                        InputKey = '96k'
                    }
                }
                @{
                    Name = '128k'
                    Parameters = @{
                        Context  = 131072
                        InputKey = '128k'
                    }
                }
                @{
                    Name = '256k'
                    Parameters = @{
                        Context  = 262144
                        InputKey = '256k'
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

        # Synthetic PP sweep. Disabled by default because it adds substantial
        # time after the real-input series. Set Enabled = $true when wanted.
        @{
            Name = 'bench-longctx-pp'
            Tool = 'bench'
            Enabled = $false

            BuildKeys = @(
                'R3ROCm'
            )

            ModelKeys = @(
                'UnslothOriginal'
            )

            Cases = @(
                @{
                    Name = 'pp-sweep'
                    Parameters = @{
                        PromptTokens = @(
                            32768
                            65536
                            98304
                            131072
                            262144
                        )
                        GenerationTokens = @(0)
                        Depths = @(0)
                    }
                }
            )
        }
    )
}
