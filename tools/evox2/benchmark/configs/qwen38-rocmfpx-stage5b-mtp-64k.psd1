@{
    SchemaVersion = 1
    Name = 'qwen38-rocmfpx-stage5b-mtp-64k'

    # Stage 5B: matched 64k MTP OFF/ON compatibility gate.
    # This is a correctness/integration comparison, not a tuning benchmark.
    #
    # Required local.psd1 keys:
    # Builds:
    #   R5RocmFpxStage5Vulkan
    # Models:
    #   AgentionRocmFp4FastPle16
    #   AgentionRocmFp4FastMtp
    # Inputs:
    #   64k

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
            Mtp              = $false
            ResourceMonitor  = $true
            ExtraArgs = @('-tb', '4', '--ctx-checkpoints', '0t')
        }

        Environment = @{
            GGML_VK_FORCE_MMVQ                  = $null
            GGML_VK_DISABLE_MMVQ                = $null
            GGML_VK_QSA_UNION                   = $null
            GGML_VK_QSA_UNION_STATS             = $null
            GGML_VK_QSA_UNION_STATS_FILE        = $null
            GGML_VK_QSA_UNION_STATS_KV_BIN      = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER         = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION     = $null
            LLAMA_MTP_DIAG                       = $null
            LLAMA_QSA_NO_POOLED_CACHE            = $null
            LLAMA_QSA_POOLED_MAX_TOKENS          = $null
            QWEN4EXP_QSA_GATHER                  = $null
            GGML_VK_QSA_UNION_MIN_KV             = $null
            LLAMA_MTP_QSA_MIN_KV                 = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE       = $null
            LLAMA_GRAPH_REUSE_DISABLE            = $null
            GGML_VK_FUSE_UNARY_MUL               = $null
            GGML_VK_SHMEM_PAD                    = $null
            GGML_VK_DENSE_WAVE32                 = $null
            GGML_VK_MOE_LEGACY_TILE_SELECTION   = $null
            GGML_VK_MOE_TILE_LOG                 = $null
            GGML_VK_PERF_LOGGER                  = $null
            GGML_VK_PERF_LOGGER_FREQUENCY        = $null
            GGML_VK_PERF_LOGGER_CONCURRENT       = $null
            GGML_VK_PERF_GET_ROWS_DETAILS        = $null
            GGML_VK_GET_ROWS_128X4               = $null
            GGML_VK_FA_SPARSE_DISABLE            = $null
            EVOX2_AB_RUN                         = $null
            EVOX2_ABBA_RUN                       = $null
        }
    }

    Jobs = @(
        @{
            Name = 'mtp-64k-ab'
            Tool = 'cli'

            BuildKeys = @('R5RocmFpxStage5Vulkan')
            ModelKeys = @('AgentionRocmFp4FastPle16')

            Cases = @(
                @{
                    Name = '64k'
                    Parameters = @{
                        Context  = 65536
                        InputKey = '64k'
                    }
                }
            )

            # Variants are adjacent for the same build/model/case.
            Variants = @(
                @{
                    Name = 'nomtp'
                    Parameters = @{}
                }
                @{
                    Name = 'mtp'
                    Parameters = @{
                        Mtp           = $true
                        DraftModelKey = 'AgentionRocmFp4FastMtp'
                        DraftMax      = 2
                        DraftPMin     = 0.0
                    }
                }
            )
        }
    )
}
