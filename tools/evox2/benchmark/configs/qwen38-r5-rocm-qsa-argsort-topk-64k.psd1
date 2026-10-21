@{
    SchemaVersion = 1
    Name = 'qwen38-r5-rocm-qsa-argsort-topk-64k'

    # Validation for investigation/rocm-qsa-argsort-topk-20261022.
    #
    # Source delta under test:
    #   qwen4exp QSA selection:
    #     ggml_top_k(...) -> ggml_argsort_top_k(...)
    #
    # Goal:
    #   1. Check whether four fresh-process greedy 64k runs become repeatable.
    #   2. Measure PP/TG cost of stable argsort-based QSA selection.
    #   3. Exercise a build produced by the unified TheRock 10.0 Build-ROCm.ps1.
    #
    # Required local.psd1 entries:
    #   Builds.R5ROCmQsaArgsortTopK
    #   Models.UnslothPle16
    #   Inputs.64k

    Settings = @{
        CooldownSeconds = 20
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
            Temperature      = 0.0
            TopP             = 0.8
            Reasoning        = 'off'
            Fit              = 'off'
            Mtp              = $false
            ResourceMonitor  = $true
            ExtraArgs = @(
                '-tb', '4',
                '--ctx-checkpoints', '0t',
                '--seed', '1234',
                '--ignore-eos',
                '--no-display-prompt'
            )
        }

        Environment = @{
            HIP_LAUNCH_BLOCKING                 = $null
            GGML_CUDA_FA_ZERO_MASKED            = $null
            GGML_CUDA_DISABLE_GRAPHS            = $null
            GGML_CUDA_DISABLE_FUSION            = $null
            LLAMA_GRAPH_REUSE_DISABLE           = $null

            LLAMA_MTP_SKIP_DENSE_INDEXER        = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION    = $null
            LLAMA_QSA_NOOP_TRACE                = $null
            LLAMA_MTP_DIAG                      = $null
            LLAMA_QSA_NO_POOLED_CACHE           = $null
            LLAMA_QSA_POOLED_MAX_TOKENS         = $null
            QWEN4EXP_QSA_GATHER                 = $null
            LLAMA_MTP_QSA_MIN_KV                = $null

            GGML_VK_QSA_UNION                   = $null
            GGML_VK_QSA_UNION_MIN_KV            = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE      = $null
            GGML_VK_FUSE_UNARY_MUL              = $null
            GGML_VK_SHMEM_PAD                   = $null
            GGML_VK_DENSE_WAVE32                = $null
            GGML_VK_PERF_LOGGER                 = $null
            GGML_VK_PERF_LOGGER_FREQUENCY       = $null
            GGML_VK_PERF_LOGGER_CONCURRENT      = $null
            GGML_VK_PERF_GET_ROWS_DETAILS       = $null
            GGML_VK_FORCE_MMVQ                  = $null
            GGML_VK_DISABLE_MMVQ                = $null
            GGML_VK_FA_SPARSE_DISABLE           = $null
            GGML_VK_MOE_TILE_LOG                = $null
            GGML_VK_MOE_LEGACY_TILE_SELECTION   = $null
            GGML_VK_GET_ROWS_128X4              = $null

            ROCM_RUNTIME_VARIANT                 = 'therock10-unified-build-script'
            ROCM_REPEATABILITY_PHASE             = 'qsa-argsort-topk'
            ROCM_REPEATABILITY_CASE              = 'qsa-argsort-topk'
            ROCM_REPEATABILITY_REP               = $null
        }
    }

    Jobs = @(
        @{
            Name = 'rocm-qsa-argsort-topk'
            Tool = 'cli'
            BuildKeys = @('R5ROCmQsaArgsortTopK')
            ModelKeys = @('UnslothPle16')

            Cases = @(
                @{
                    Name = '64k'
                    Parameters = @{
                        Context = 65536
                        InputKey = '64k'
                    }
                }
            )

            Variants = @(
                @{
                    Name = 'argsort-r1'
                    Environment = @{ ROCM_REPEATABILITY_REP = '1' }
                },
                @{
                    Name = 'argsort-r2'
                    Environment = @{ ROCM_REPEATABILITY_REP = '2' }
                },
                @{
                    Name = 'argsort-r3'
                    Environment = @{ ROCM_REPEATABILITY_REP = '3' }
                },
                @{
                    Name = 'argsort-r4'
                    Environment = @{ ROCM_REPEATABILITY_REP = '4' }
                }
            )
        }
    )
}
