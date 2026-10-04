@{
    SchemaVersion = 1
    Name = 'qwen38-r4-getrows-128x4-64k'

    # One opt-in GET_ROWS binary; Original 64k, MTP OFF, legacy MoE fixed.
    # Use -OnlyJob profile first, then -OnlyJob normal after checking the logs.
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
            GenerationTokens = 128
            PromptCacheMiB   = 0
            Temperature      = 0.2
            TopP             = 0.8
            Reasoning        = 'off'
            Fit              = 'off'
            Mtp              = $false
            ResourceMonitor  = $true

            ExtraArgs = @(
                '-tb'
                '4'
                '--ctx-checkpoints'
                '0t'
            )
        }

        # Clear inherited experiment overrides for each child; the runner
        # restores the caller's environment afterward.
        Environment = @{
            LLAMA_MTP_SKIP_DENSE_INDEXER        = $null
            LLAMA_MTP_DIAG = $null
            LLAMA_QSA_NO_POOLED_CACHE       = $null
            LLAMA_QSA_POOLED_MAX_TOKENS     = $null
            QWEN4EXP_QSA_GATHER             = $null
            GGML_VK_QSA_UNION_MIN_KV        = $null
            LLAMA_MTP_QSA_MIN_KV            = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE  = $null
            LLAMA_GRAPH_REUSE_DISABLE      = $null
            GGML_VK_FUSE_UNARY_MUL          = $null
            GGML_VK_SHMEM_PAD               = $null
            GGML_VK_DENSE_WAVE32            = $null
            GGML_VK_PERF_LOGGER            = $null
            GGML_VK_PERF_LOGGER_FREQUENCY  = $null
            GGML_VK_PERF_LOGGER_CONCURRENT = $null
            GGML_VK_FORCE_MMVQ             = $null
            GGML_VK_DISABLE_MMVQ           = $null
            GGML_VK_MOE_LEGACY_TILE_SELECTION = '1'
            GGML_VK_MOE_TILE_LOG              = $null
            GGML_VK_PERF_GET_ROWS_DETAILS      = $null
            GGML_VK_GET_ROWS_128X4             = $null
            EVOX2_AB_RUN                   = $null
            EVOX2_ABBA_RUN                 = $null
        }
    }

    Jobs = @(
        @{
            Name = 'profile'
            Tool = 'cli'
            BuildKeys = @('R4GetRows128x4Vulkan')
            ModelKeys = @('UnslothOriginal')
            Cases = @(
                @{
                    Name = '64k'
                    Parameters = @{ Context = 65536; InputKey = '64k' }
                }
            )
            Environment = @{
                GGML_VK_PERF_LOGGER = '1'
                GGML_VK_PERF_LOGGER_FREQUENCY = '1'
                GGML_VK_PERF_GET_ROWS_DETAILS = '1'
            }
            Variants = @(
                @{
                    Name = 'A1-off'
                    Parameters = @{}
                    Environment = @{
                        GGML_VK_GET_ROWS_128X4 = '0'
                        EVOX2_ABBA_RUN = 'A1'
                    }
                }
                @{
                    Name = 'B1-on'
                    Parameters = @{}
                    Environment = @{
                        GGML_VK_GET_ROWS_128X4 = '1'
                        EVOX2_ABBA_RUN = 'B1'
                    }
                }
            )
        }
        @{
            Name = 'normal'
            Tool = 'cli'
            # Longer, fixed-length decode avoids comparing different EOS lengths.
            Parameters = @{
                GenerationTokens = 512
                ExtraArgs = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--ignore-eos')
            }
            BuildKeys = @('R4GetRows128x4Vulkan')
            ModelKeys = @('UnslothOriginal')
            Cases = @(
                @{
                    Name = '64k'
                    Parameters = @{ Context = 65536; InputKey = '64k' }
                }
            )
            Variants = @(
                @{
                    Name = 'A1-off'
                    Parameters = @{}
                    Environment = @{
                        GGML_VK_GET_ROWS_128X4 = '0'
                        EVOX2_ABBA_RUN = 'A1'
                    }
                }
                @{
                    Name = 'B1-on'
                    Parameters = @{}
                    Environment = @{
                        GGML_VK_GET_ROWS_128X4 = '1'
                        EVOX2_ABBA_RUN = 'B1'
                    }
                }
                @{
                    Name = 'B2-on'
                    Parameters = @{}
                    Environment = @{
                        GGML_VK_GET_ROWS_128X4 = '1'
                        EVOX2_ABBA_RUN = 'B2'
                    }
                }
                @{
                    Name = 'A2-off'
                    Parameters = @{}
                    Environment = @{
                        GGML_VK_GET_ROWS_128X4 = '0'
                        EVOX2_ABBA_RUN = 'A2'
                    }
                }
            )
        }
    )
}
