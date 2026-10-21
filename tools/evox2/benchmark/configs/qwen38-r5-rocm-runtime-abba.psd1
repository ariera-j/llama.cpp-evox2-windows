@{
    SchemaVersion = 1
    Name = 'qwen38-r5-rocm-runtime-abba'

    # Same llama.cpp executable/backend DLLs and same model/input.
    # A = historical mixed runtime:
    #     TheRock amdhip/comgr/kpack + HIP SDK 7.2 hipBLAS/rocBLAS/hipBLASLt.
    # B = pure TheRock 10 runtime staged beside the identical executable:
    #     TheRock amdhip/comgr/kpack/hipBLAS/rocBLAS/rocSOLVER/libhipBLASLt/origami.
    #
    # IMPORTANT:
    # - Define both BuildKeys in local.psd1 (see comments below).
    # - The executable and ggml-hip.dll SHA256 must remain identical across A/B.
    # - ROCM_RUNTIME_VARIANT is a provenance label only; no llama.cpp code consumes it.
    # - This plan intentionally uses MTP OFF to isolate the runtime-library comparison.

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
                '--ignore-eos'
            )
        }

        # Clear unrelated experimental toggles so the DLL stack is the intended A/B.
        # Do not modify HIP_PATH/ROCM_PATH/PATH here: keep the parent environment
        # identical for A/B and let the executable-directory DLLs determine B.
        Environment = @{
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
            LLAMA_GRAPH_REUSE_DISABLE           = $null
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
            EVOX2_AB_RUN                        = $null
            EVOX2_ABBA_RUN                      = $null
            ROCM_RUNTIME_VARIANT                = $null
        }
    }

    # Four jobs are intentional. Invoke-BenchmarkMatrix expands BuildKeys outside
    # Variants, so putting both BuildKeys in one job would produce AABB rather
    # than the required A1-B1-B2-A2 execution order.
    Jobs = @(
        @{
            Name = 'runtime-A1-mixed'; Tool = 'cli'
            BuildKeys = @('R5ROCmRuntimeMixed')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k' } }
            )
            Variants = @(
                @{
                    Name = 'A1'
                    Environment = @{
                        ROCM_RUNTIME_VARIANT = 'mixed-hip72-blas'
                        EVOX2_ABBA_RUN = 'A1'
                    }
                }
            )
        }

        @{
            Name = 'runtime-B1-therock10'; Tool = 'cli'
            BuildKeys = @('R5ROCmRuntimeTheRock10')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k' } }
            )
            Variants = @(
                @{
                    Name = 'B1'
                    Environment = @{
                        ROCM_RUNTIME_VARIANT = 'therock10-pure'
                        EVOX2_ABBA_RUN = 'B1'
                    }
                }
            )
        }

        @{
            Name = 'runtime-B2-therock10'; Tool = 'cli'
            BuildKeys = @('R5ROCmRuntimeTheRock10')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k' } }
            )
            Variants = @(
                @{
                    Name = 'B2'
                    Environment = @{
                        ROCM_RUNTIME_VARIANT = 'therock10-pure'
                        EVOX2_ABBA_RUN = 'B2'
                    }
                }
            )
        }

        @{
            Name = 'runtime-A2-mixed'; Tool = 'cli'
            BuildKeys = @('R5ROCmRuntimeMixed')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k' } }
            )
            Variants = @(
                @{
                    Name = 'A2'
                    Environment = @{
                        ROCM_RUNTIME_VARIANT = 'mixed-hip72-blas'
                        EVOX2_ABBA_RUN = 'A2'
                    }
                }
            )
        }
    )
}
