@{
    SchemaVersion = 1
    Name = 'qwen38-common005-vulkan-longctx'

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

        # Keep COMMON-004 enabled so the A/B isolates COMMON-005.
        Environment = @{
            LLAMA_QSA_NO_POOLED_CACHE    = $null
            LLAMA_QSA_POOLED_MAX_TOKENS = '32'
        }
    }

    Jobs = @(
        @{
            Name = 'common005-vulkan-64k-ab'
            Tool = 'cli'

            BuildKeys = @(
                'Common005Vulkan'
            )

            ModelKeys = @(
                'UnslothPle16'
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

            # Initial backend crossover/correctness gate: fallback OFF -> gather ON.
            Variants = @(
                @{
                    Name = 'B1-gather-off'
                    Parameters = @{}
                    Environment = @{
                        EVOX2_AB_RUN        = 'B1'
                        QWEN4EXP_QSA_GATHER = '0'
                    }
                }
                @{
                    Name = 'A1-gather-on'
                    Parameters = @{}
                    Environment = @{
                        EVOX2_AB_RUN        = 'A1'
                        QWEN4EXP_QSA_GATHER = '1'
                    }
                }
            )
        }

        @{
            Name = 'common005-vulkan-longctx-abba'
            Tool = 'cli'

            BuildKeys = @(
                'Common005Vulkan'
            )

            ModelKeys = @(
                'UnslothPle16'
            )

            # Case-major execution: complete 128k ABBA, then complete 256k ABBA.
            Cases = @(
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

            # Exact execution order within each case: A1 -> B1 -> B2 -> A2.
            # A = COMMON-005 gather ON, B = existing Vulkan sparse-FA fallback.
            Variants = @(
                @{
                    Name = 'A1-gather-on'
                    Parameters = @{}
                    Environment = @{
                        EVOX2_ABBA_RUN      = 'A1'
                        QWEN4EXP_QSA_GATHER = '1'
                    }
                }
                @{
                    Name = 'B1-gather-off'
                    Parameters = @{}
                    Environment = @{
                        EVOX2_ABBA_RUN      = 'B1'
                        QWEN4EXP_QSA_GATHER = '0'
                    }
                }
                @{
                    Name = 'B2-gather-off'
                    Parameters = @{}
                    Environment = @{
                        EVOX2_ABBA_RUN      = 'B2'
                        QWEN4EXP_QSA_GATHER = '0'
                    }
                }
                @{
                    Name = 'A2-gather-on'
                    Parameters = @{}
                    Environment = @{
                        EVOX2_ABBA_RUN      = 'A2'
                        QWEN4EXP_QSA_GATHER = '1'
                    }
                }
            )
        }
    )
}
