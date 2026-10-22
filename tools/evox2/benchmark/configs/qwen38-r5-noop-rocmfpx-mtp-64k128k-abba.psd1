@{
    SchemaVersion = 1
    Name = 'qwen38-r5-noop-rocmfpx-mtp-64k128k-abba'

    # Optimized r5 integrated target + matching MTP draft comparison.
    # Required local.psd1 keys: R5NoopRocmFpxVulkan;
    #   AgentionRocmFp4FastPle16, AgentionRocmFp4FastMtp;
    #   UnslothPle16, UnslothMtp; and relevant Inputs (32k or 64k/128k).
    # Rehearsal binary b11588 validated ROCmFP4 MTP; validate Unsloth MTP on 32k first.
    # These are separate draft/model SYSTEM comparisons, not target-only quantization tests.
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
            GenerationTokens = 512
            PromptCacheMiB   = 0
            Temperature      = 0
            TopP             = 0.8
            Reasoning        = 'off'
            Fit              = 'off'
            Mtp              = $true
            DraftMax         = 2
            DraftPMin        = 0.0
            ResourceMonitor  = $true
            ExtraArgs        = @('-tb', '4', '--ctx-checkpoints', '0t')
        }
        Environment = @{
            GGML_VK_QSA_UNION                  = '1'
            GGML_VK_QSA_UNION_MIN_KV           = '1'
            LLAMA_MTP_SKIP_DENSE_INDEXER      = '1'
            LLAMA_QSA_SKIP_NOOP_INVALIDATION  = '1'
            GGML_VK_FORCE_MMVQ                      = $null
            GGML_VK_DISABLE_MMVQ                    = $null
            GGML_VK_QSA_UNION_STATS                 = $null
            GGML_VK_QSA_UNION_STATS_FILE            = $null
            GGML_VK_QSA_UNION_STATS_KV_BIN          = $null
            LLAMA_MTP_DIAG                          = $null
            LLAMA_QSA_NO_POOLED_CACHE               = $null
            LLAMA_QSA_POOLED_MAX_TOKENS             = $null
            QWEN4EXP_QSA_GATHER                     = $null
            LLAMA_MTP_QSA_MIN_KV                    = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE          = $null
            LLAMA_GRAPH_REUSE_DISABLE               = $null
            GGML_VK_FUSE_UNARY_MUL                  = $null
            GGML_VK_SHMEM_PAD                       = $null
            GGML_VK_DENSE_WAVE32                    = $null
            GGML_VK_MOE_LEGACY_TILE_SELECTION       = $null
            GGML_VK_MOE_TILE_LOG                    = $null
            GGML_VK_PERF_LOGGER                     = $null
            GGML_VK_PERF_LOGGER_FREQUENCY           = $null
            GGML_VK_PERF_LOGGER_CONCURRENT          = $null
            GGML_VK_PERF_GET_ROWS_DETAILS           = $null
            GGML_VK_GET_ROWS_128X4                  = $null
            GGML_VK_FA_SPARSE_DISABLE               = $null
            EVOX2_AB_RUN                            = $null
        }
    }

    Jobs = @(
        @{
            Name = '64k-01-unsloth'
            Tool = 'cli'
            BuildKeys = @('R5NoopRocmFpxVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(@{
                Name = '64k'
                Parameters = @{ Context = 65536; InputKey = '64k' }
            })
            Variants = @(@{
                Name = 'mtp-unsloth'
                Parameters = @{ DraftModelKey = 'UnslothMtp' }
                Environment = @{ EVOX2_ABBA_RUN = '64k-01-unsloth' }
            })
        }
        @{
            Name = '64k-02-rocmfp4'
            Tool = 'cli'
            BuildKeys = @('R5NoopRocmFpxVulkan')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(@{
                Name = '64k'
                Parameters = @{ Context = 65536; InputKey = '64k' }
            })
            Variants = @(@{
                Name = 'mtp-rocmfp4'
                Parameters = @{ DraftModelKey = 'AgentionRocmFp4FastMtp' }
                Environment = @{ EVOX2_ABBA_RUN = '64k-02-rocmfp4' }
            })
        }
        @{
            Name = '64k-03-rocmfp4'
            Tool = 'cli'
            BuildKeys = @('R5NoopRocmFpxVulkan')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(@{
                Name = '64k'
                Parameters = @{ Context = 65536; InputKey = '64k' }
            })
            Variants = @(@{
                Name = 'mtp-rocmfp4'
                Parameters = @{ DraftModelKey = 'AgentionRocmFp4FastMtp' }
                Environment = @{ EVOX2_ABBA_RUN = '64k-03-rocmfp4' }
            })
        }
        @{
            Name = '64k-04-unsloth'
            Tool = 'cli'
            BuildKeys = @('R5NoopRocmFpxVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(@{
                Name = '64k'
                Parameters = @{ Context = 65536; InputKey = '64k' }
            })
            Variants = @(@{
                Name = 'mtp-unsloth'
                Parameters = @{ DraftModelKey = 'UnslothMtp' }
                Environment = @{ EVOX2_ABBA_RUN = '64k-04-unsloth' }
            })
        }
        @{
            Name = '128k-05-rocmfp4'
            Tool = 'cli'
            BuildKeys = @('R5NoopRocmFpxVulkan')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(@{
                Name = '128k'
                Parameters = @{ Context = 131072; InputKey = '128k' }
            })
            Variants = @(@{
                Name = 'mtp-rocmfp4'
                Parameters = @{ DraftModelKey = 'AgentionRocmFp4FastMtp' }
                Environment = @{ EVOX2_ABBA_RUN = '128k-05-rocmfp4' }
            })
        }
        @{
            Name = '128k-06-unsloth'
            Tool = 'cli'
            BuildKeys = @('R5NoopRocmFpxVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(@{
                Name = '128k'
                Parameters = @{ Context = 131072; InputKey = '128k' }
            })
            Variants = @(@{
                Name = 'mtp-unsloth'
                Parameters = @{ DraftModelKey = 'UnslothMtp' }
                Environment = @{ EVOX2_ABBA_RUN = '128k-06-unsloth' }
            })
        }
        @{
            Name = '128k-07-unsloth'
            Tool = 'cli'
            BuildKeys = @('R5NoopRocmFpxVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(@{
                Name = '128k'
                Parameters = @{ Context = 131072; InputKey = '128k' }
            })
            Variants = @(@{
                Name = 'mtp-unsloth'
                Parameters = @{ DraftModelKey = 'UnslothMtp' }
                Environment = @{ EVOX2_ABBA_RUN = '128k-07-unsloth' }
            })
        }
        @{
            Name = '128k-08-rocmfp4'
            Tool = 'cli'
            BuildKeys = @('R5NoopRocmFpxVulkan')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(@{
                Name = '128k'
                Parameters = @{ Context = 131072; InputKey = '128k' }
            })
            Variants = @(@{
                Name = 'mtp-rocmfp4'
                Parameters = @{ DraftModelKey = 'AgentionRocmFp4FastMtp' }
                Environment = @{ EVOX2_ABBA_RUN = '128k-08-rocmfp4' }
            })
        }
    )
}
