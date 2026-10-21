@{
    SchemaVersion = 1
    Name = 'qwen38-rocmfpx-stage5-mtp-gate'

    # Stage 5A: MTP sidecar compatibility gate for the ROCmFPx Vulkan port.
    #
    # Purpose:
    #   1. Load the existing ROCmFP4-FAST MTP sidecar without compatibility
    #      patches using a cheap 4k allocation smoke.
    #   2. If that succeeds, run the standard 32k real-input MTP workload and
    #      inspect draft acceptance, output coherence and GPU placement.
    #
    # ContinueOnError is false deliberately: if the sidecar fails to load at
    # 4k (for example because it uses the old output_hc_* tensor layout), stop
    # before spending time on the 32k run.
    #
    # Required local.psd1 keys:
    #
    # Builds:
    #   R5RocmFpxStage5Vulkan  (build after the Stage-5 old-HC compatibility patch)
    #
    # Models:
    #   AgentionRocmFp4FastPle16
    #   AgentionRocmFp4FastMtp
    #
    # Inputs:
    #   32k

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
            Mtp              = $true
            DraftModelKey    = 'AgentionRocmFp4FastMtp'
            DraftMax         = 2
            DraftPMin        = 0.0
            ResourceMonitor  = $true

            ExtraArgs = @(
                '-tb'
                '4'
                '--ctx-checkpoints'
                '0t'
            )
        }

        # Keep Stage 5 isolated from all later MTP/QSA/Vulkan experiments.
        # This gate is compatibility/correctness only.
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
            Name = 'mtp-sidecar-load'
            Tool = 'cli'

            BuildKeys = @(
                'R5RocmFpxStage5Vulkan'
            )

            ModelKeys = @(
                'AgentionRocmFp4FastPle16'
            )

            Cases = @(
                @{
                    Name = '4k-allocation'
                    Parameters = @{
                        Context        = 4096
                        AllocationOnly = $true
                    }
                }
            )

            Variants = @(
                @{
                    Name = 'mtp'
                    Parameters = @{
                        # AllocationOnly always generates 32 tokens.
                        GenerationTokens = 32
                    }
                }
            )
        }

        @{
            Name = 'mtp-32k-real-input'
            Tool = 'cli'

            BuildKeys = @(
                'R5RocmFpxStage5Vulkan'
            )

            ModelKeys = @(
                'AgentionRocmFp4FastPle16'
            )

            Cases = @(
                @{
                    Name = '32k'
                    Parameters = @{
                        Context  = 32768
                        InputKey = '32k'
                    }
                }
            )

            Variants = @(
                @{
                    Name = 'mtp'
                    Parameters = @{}
                }
            )
        }
    )
}
