@{
    SchemaVersion = 1
    Name = 'qwen38-mtp'

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
    }

    Jobs = @(
        # Side-by-side no-MTP/MTP measurements for the converted PLE16 base.
        # The runner expands Cases first and Variants last, so nomtp and mtp
        # stay adjacent for each context.
        @{
            Name = 'cli-mtp-ab'
            Tool = 'cli'

            # Add R3Vulkan if the same A/B series is wanted on Vulkan.
            BuildKeys = @(
                'R3ROCm'
            )

            ModelKeys = @(
                'UnslothPle16'
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
            )

            Variants = @(
                @{
                    Name = 'nomtp'
                    Parameters = @{}
                }
                @{
                    Name = 'mtp'
                    Parameters = @{
                        Mtp           = $true
                        DraftModelKey = 'UnslothMtp'
                        DraftMax      = 2
                        DraftPMin     = 0.0
                    }
                }
            )
        }
    )
}
