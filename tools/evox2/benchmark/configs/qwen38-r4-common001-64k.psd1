@{
    SchemaVersion = 1
    Name = 'qwen38-r4-common001-64k'

    # r4 COMMON-001 validation:
    # - same 64k real input
    # - Original joined PLE vs PLE16 split PLE
    # - Vulkan and ROCm
    # - MTP off
    # - Vulkan uses legacy MoE tile selection for the matched pre-port reference
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

        # Clear inherited experiment/profiler overrides for every child run.
        # Invoke-BenchmarkMatrix.ps1 restores the caller environment afterward.
        Environment = @{
            LLAMA_MTP_DIAG = $null
            GGML_VK_GET_ROWS_128X4          = $null
            LLAMA_QSA_NO_POOLED_CACHE         = $null
            LLAMA_QSA_POOLED_MAX_TOKENS       = $null
            QWEN4EXP_QSA_GATHER               = $null
            GGML_VK_QSA_UNION_MIN_KV          = $null
            LLAMA_MTP_QSA_MIN_KV              = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE    = $null
            LLAMA_GRAPH_REUSE_DISABLE         = $null
            GGML_VK_FUSE_UNARY_MUL            = $null
            GGML_VK_SHMEM_PAD                 = $null
            GGML_VK_DENSE_WAVE32              = $null
            GGML_VK_MOE_LEGACY_TILE_SELECTION = $null
            GGML_VK_MOE_TILE_LOG              = $null
            GGML_VK_PERF_LOGGER               = $null
            GGML_VK_PERF_GET_ROWS_DETAILS     = $null
            EVOX2_AB_RUN                       = $null
            EVOX2_ABBA_RUN                     = $null
        }
    }

    Jobs = @(
        @{
            Name = 'common001-64k-vulkan'
            Tool = 'cli'

            BuildKeys = @(
                'R4Vulkan'
            )

            ModelKeys = @(
                'UnslothOriginal'
                'UnslothPle16'
            )

            Environment = @{
                # Match the r4 pre-port 64k Vulkan reference.
                GGML_VK_MOE_LEGACY_TILE_SELECTION = '1'
            }

            Cases = @(
                @{
                    Name = '64k'
                    Parameters = @{
                        Context  = 65536
                        InputKey = '64k'
                    }
                }
            )

            Variants = @(
                @{
                    Name = 'legacy-moe-nomtp'
                    Parameters = @{}
                }
            )
        }

        @{
            Name = 'common001-64k-rocm'
            Tool = 'cli'

            BuildKeys = @(
                'R4ROCm'
            )

            ModelKeys = @(
                'UnslothOriginal'
                'UnslothPle16'
            )

            # No Vulkan-only override on ROCm.
            Environment = @{
                GGML_VK_MOE_LEGACY_TILE_SELECTION = $null
            }

            Cases = @(
                @{
                    Name = '64k'
                    Parameters = @{
                        Context  = 65536
                        InputKey = '64k'
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
