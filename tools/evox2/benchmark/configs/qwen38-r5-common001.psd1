@{
    SchemaVersion = 1
    Name = 'qwen38-r5-common001'

    # Pinned source is recorded in docs/evox2/CURRENT-REFRESH.json.
    # No downstream QSA patches. Run only after clean build/load smoke passes.
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

        # Clear inherited experiment overrides for each child; the runner
        # restores the caller's environment afterward. These are not patches.
        Environment = @{
            GGML_VK_QSA_UNION                = $null
            GGML_VK_QSA_UNION_STATS          = $null
            GGML_VK_QSA_UNION_STATS_FILE     = $null
            GGML_VK_QSA_UNION_STATS_KV_BIN   = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER        = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION    = $null
            LLAMA_MTP_DIAG = $null
            GGML_VK_GET_ROWS_128X4          = $null
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
            GGML_VK_MOE_LEGACY_TILE_SELECTION = $null
            GGML_VK_MOE_TILE_LOG              = $null
            GGML_VK_PERF_GET_ROWS_DETAILS      = $null
            EVOX2_AB_RUN                   = $null
            EVOX2_ABBA_RUN                 = $null
        }
    }

    Jobs = @(
        @{
            Name = 'clean-longctx'
            Tool = 'cli'

            BuildKeys = @('R5Common001Vulkan', 'R5Common001ROCm')
            # Original multi-file GGUF with joined PLE tensor layout; pass
            # shard 00001. A single physically joined file is not required.
            ModelKeys = @('UnslothOriginal', 'UnslothPle16')

            # Gate with -OnlyCase 64k, then 128k, then 256k.
            Cases = @(
                @{
                    Name = '64k'
                    Parameters = @{
                        Context  = 65536
                        InputKey = '64k'
                    }
                }
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
                    Name = 'clean-nomtp'
                    Parameters = @{}
                }
            )
        }
    )
}

