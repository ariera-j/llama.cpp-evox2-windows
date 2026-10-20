@{
    SchemaVersion = 1
    Name = 'qwen38-rocmfpx-stage3-agention-longctx'

    # Stage 4 long-context comparison for the ROCmFPx Vulkan port.
    #
    # Run order is intentionally matched by context to reduce time/thermal drift:
    #   1. r5 Stage-3 Vulkan 128k
    #   2. current AgentionAI dedicated fork 128k
    #   3. r5 Stage-3 Vulkan 256k
    #   4. current AgentionAI dedicated fork 256k
    #
    # Both builds use the same ROCmFP4-FAST v2 PLE16 model, real-input corpus,
    # llama-cli measurement wrapper and inference parameters.
    #
    # Required local.psd1 keys:
    #
    # Builds:
    #   R5RocmFpxStage3Vulkan
    #   AgentionRocmFpxVulkan
    #
    # Model:
    #   AgentionRocmFp4FastPle16
    #
    # Inputs:
    #   128k
    #   256k

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

            ExtraArgs = @(
                '-tb'
                '4'
                '--ctx-checkpoints'
                '0t'
            )
        }

        # Remove inherited experiment/profiler settings so this is a clean
        # normal-dispatch comparison. In particular, do not carry the
        # GGML_VK_FORCE_MMVQ=1 setting used by the Stage-3 correctness gate.
        Environment = @{
            GGML_VK_FORCE_MMVQ                 = $null
            GGML_VK_QSA_UNION                  = $null
            GGML_VK_QSA_UNION_STATS            = $null
            GGML_VK_QSA_UNION_STATS_FILE       = $null
            GGML_VK_QSA_UNION_STATS_KV_BIN     = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER        = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION    = $null
            LLAMA_MTP_DIAG                      = $null
            GGML_VK_GET_ROWS_128X4              = $null
            LLAMA_QSA_NO_POOLED_CACHE           = $null
            LLAMA_QSA_POOLED_MAX_TOKENS         = $null
            QWEN4EXP_QSA_GATHER                 = $null
            GGML_VK_QSA_UNION_MIN_KV            = $null
            LLAMA_MTP_QSA_MIN_KV                = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE      = $null
            LLAMA_GRAPH_REUSE_DISABLE           = $null
            GGML_VK_FUSE_UNARY_MUL              = $null
            GGML_VK_SHMEM_PAD                   = $null
            GGML_VK_DENSE_WAVE32                = $null
            GGML_VK_MOE_LEGACY_TILE_SELECTION  = $null
            GGML_VK_MOE_TILE_LOG                = $null
            GGML_VK_PERF_LOGGER                 = $null
            GGML_VK_PERF_GET_ROWS_DETAILS       = $null
            EVOX2_AB_RUN                        = $null
            EVOX2_ABBA_RUN                      = $null
        }
    }

    Jobs = @(
        @{
            Name = 'rocmfpx-stage3-vs-agention-longctx'
            Tool = 'cli'

            # Invoke-BenchmarkMatrix expands Case -> BuildKey, so this produces
            # matched pairs at each context:
            #   128k Stage3 -> 128k Agention -> 256k Stage3 -> 256k Agention.
            BuildKeys = @(
                'R5RocmFpxStage3Vulkan'
                'AgentionRocmFpxVulkan'
            )

            ModelKeys = @(
                'AgentionRocmFp4FastPle16'
            )

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

            Variants = @(
                @{
                    Name = 'nomtp'
                    Parameters = @{}
                }
            )
        }
    )
}
