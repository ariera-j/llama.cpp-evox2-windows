@{
    SchemaVersion = 1
    Name = 'qwen38-common004-ab-256k'

    Settings = @{
        CooldownSeconds = 10
        ContinueOnError = $false
    }

    Defaults = @{
        CliParameters = @{
            KvType           = 'f16'
            UBatch           = 1024
            Batch            = 2048
            Threads          = 4
            GpuLayers        = 999
            CpuMoe           = 0
            FlashAttn        = 'auto'
            Verbosity        = 4
            GenerationTokens = 1024
            PromptCacheMiB   = 0
            Temperature      = 0.2
            TopP             = 0.8
            Reasoning        = 'off'
            Fit              = 'off'
            ResourceMonitor  = $true

            ExtraArgs = @(
                '-tb'
                '4'
                '--ctx-checkpoints'
                '0t'
            )
        }
    }

    Jobs = @(
        @{
            Name = 'common004-256k-ab'
            Tool = 'cli'

            BuildKeys = @(
                'Common004Vulkan'
            )

            ModelKeys = @(
                'UnslothPle16'
            )

            Cases = @(
                @{
                    Name = '256k'
                    Parameters = @{
                        Context  = 262144
                        InputKey = '256k'
                    }
                }
            )

            # Two-run validation only.
            # Run OFF first and ON second so any time/thermal drift makes the
            # COMMON-004 result conservative rather than artificially favorable.
            Variants = @(
                @{
                    Name = 'B1-pooled-off'
                    Parameters = @{}
                    Environment = @{
                        EVOX2_ABBA_RUN              = 'B1'
                        LLAMA_QSA_NO_POOLED_CACHE   = '1'
                        LLAMA_QSA_POOLED_MAX_TOKENS = '32'
                    }
                }
                @{
                    Name = 'A1-pooled-on'
                    Parameters = @{}
                    Environment = @{
                        EVOX2_ABBA_RUN              = 'A1'
                        LLAMA_QSA_NO_POOLED_CACHE   = $null
                        LLAMA_QSA_POOLED_MAX_TOKENS = '32'
                    }
                }
            )
        }
    )
}
