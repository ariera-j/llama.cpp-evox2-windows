@{
    SchemaVersion = 1
    Name = 'qwen38-common004-abba-128k'

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
            Name = 'common004-128k-abba'
            Tool = 'cli'

            BuildKeys = @(
                'Common004Vulkan'
            )

            ModelKeys = @(
                'UnslothPle16'
            )

            Cases = @(
                @{
                    Name = '128k'
                    Parameters = @{
                        Context  = 131072
                        InputKey = '128k'
                    }
                }
            )

            # Exact execution order: A1 -> B1 -> B2 -> A2.
            # EVOX2_ABBA_RUN is only a uniqueness tag for the matrix runner.
            Variants = @(
                @{
                    Name = 'A1-pooled-on'
                    Parameters = @{}
                    Environment = @{
                        EVOX2_ABBA_RUN              = 'A1'
                        LLAMA_QSA_NO_POOLED_CACHE   = $null
                        LLAMA_QSA_POOLED_MAX_TOKENS = '32'
                    }
                }
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
                    Name = 'B2-pooled-off'
                    Parameters = @{}
                    Environment = @{
                        EVOX2_ABBA_RUN              = 'B2'
                        LLAMA_QSA_NO_POOLED_CACHE   = '1'
                        LLAMA_QSA_POOLED_MAX_TOKENS = '32'
                    }
                }
                @{
                    Name = 'A2-pooled-on'
                    Parameters = @{}
                    Environment = @{
                        EVOX2_ABBA_RUN              = 'A2'
                        LLAMA_QSA_NO_POOLED_CACHE   = $null
                        LLAMA_QSA_POOLED_MAX_TOKENS = '32'
                    }
                }
            )
        }
    )
}
