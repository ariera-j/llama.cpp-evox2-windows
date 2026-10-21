@{
    SchemaVersion = 1
    Name = 'qwen38-r5-noop-rocmfpx-integrated-smoke'

    # Final bounded integration rehearsal:
    # ROCmFP4 target + ROCmFP4 MTP sidecar + VULKAN-002 grouped union
    # + MTP-DENSE + MTP-NOOP, all enabled together.
    #
    # Required local.psd1 keys:
    # Builds:
    #   R5NoopRocmFpxVulkan
    # Models:
    #   AgentionRocmFp4FastPle16
    #   AgentionRocmFp4FastMtp

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
            Temperature      = 0.0
            TopP             = 0.8
            Reasoning        = 'off'
            Fit              = 'off'
            Mtp              = $true
            DraftModelKey    = 'AgentionRocmFp4FastMtp'
            DraftMax         = 2
            DraftPMin        = 0.0
            ResourceMonitor  = $true
            ExtraArgs = @(
                '-tb', '4',
                '--ctx-checkpoints', '0t',
                '--seed', '1234',
                '--ignore-eos',
                '--top-k', '1'
            )
        }

        Environment = @{
            LLAMA_MTP_SKIP_DENSE_INDEXER         = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION     = $null
            LLAMA_QSA_NOOP_TRACE                 = $null
            LLAMA_MTP_DIAG                       = $null
            LLAMA_QSA_NO_POOLED_CACHE            = $null
            LLAMA_QSA_POOLED_MAX_TOKENS          = $null
            QWEN4EXP_QSA_GATHER                  = $null
            GGML_VK_QSA_UNION                    = $null
            GGML_VK_QSA_UNION_MIN_KV             = $null
            LLAMA_MTP_QSA_MIN_KV                 = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE       = $null
            LLAMA_GRAPH_REUSE_DISABLE            = $null
            GGML_VK_FUSE_UNARY_MUL               = $null
            GGML_VK_SHMEM_PAD                    = $null
            GGML_VK_DENSE_WAVE32                 = $null
            GGML_VK_PERF_LOGGER                  = $null
            GGML_VK_PERF_LOGGER_FREQUENCY        = $null
            GGML_VK_PERF_LOGGER_CONCURRENT       = $null
            GGML_VK_PERF_GET_ROWS_DETAILS        = $null
            GGML_VK_FORCE_MMVQ                   = $null
            GGML_VK_DISABLE_MMVQ                 = $null
            GGML_VK_FA_SPARSE_DISABLE            = $null
            GGML_VK_MOE_TILE_LOG                 = $null
            GGML_VK_MOE_LEGACY_TILE_SELECTION   = $null
            GGML_VK_GET_ROWS_128X4               = $null
            EVOX2_AB_RUN                         = $null
            EVOX2_ABBA_RUN                       = $null
        }
    }

    Jobs = @(
        @{
            Name = 'all-on-short'
            Tool = 'cli'

            BuildKeys = @('R5NoopRocmFpxVulkan')
            ModelKeys = @('AgentionRocmFp4FastPle16')

            Environment = @{
                # Force the grouped-union path to be eligible even on the
                # short integration input. This is a correctness stress gate,
                # not a performance setting.
                GGML_VK_QSA_UNION                = '1'
                GGML_VK_QSA_UNION_MIN_KV         = '1'
                LLAMA_MTP_SKIP_DENSE_INDEXER     = '1'
                LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
                LLAMA_QSA_NOOP_TRACE             = '0'
                LLAMA_MTP_DIAG                   = 'off'
            }

            Cases = @(
                @{
                    Name = 'short'
                    Parameters = @{
                        Context   = 32768
                        InputFile = 'tools\evox2\benchmark\inputs\mtp-short.txt'
                    }
                }
            )

            Variants = @(
                @{
                    Name = 'union-dense-noop-rocmfpx'
                    Parameters = @{}
                }
            )
        }
    )
}
