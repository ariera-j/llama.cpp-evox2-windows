@{
    SchemaVersion = 1
    Name = 'qwen38-r4-mtp-diagnostics'

    # Focused attribution runs; not a performance comparison.
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
            Temperature      = 0.2
            TopP             = 0.8
            Reasoning        = 'off'
            Fit              = 'off'
            Mtp              = $false
            ResourceMonitor  = $true
            ExtraArgs = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--ignore-eos')
        }

        # Prevent inherited diagnostics/profilers from changing normal timings.
        # The runner restores the caller's environment after each child.
        Environment = @{
            LLAMA_MTP_DIAG                     = $null
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
            GGML_VK_QSA_UNION                   = $null
            EVOX2_AB_RUN                        = $null
            EVOX2_ABBA_RUN                      = $null
        }
    }

    Jobs = @(
        @{
            Name = 'vulkan-128k-on'; Tool = 'cli'
            BuildKeys = @('R4QsaUnionVulkan'); ModelKeys = @('UnslothPle16')
            Environment = @{
                GGML_VK_MOE_LEGACY_TILE_SELECTION = '1'
                GGML_VK_GET_ROWS_128X4 = '0'
                GGML_VK_QSA_UNION = '1'
                LLAMA_MTP_DIAG = 'wall'
            }
            Cases = @(@{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k' } })
            Variants = @(@{ Name = 'on-wall'; Parameters = @{ Mtp = $true; DraftModelKey = 'UnslothMtp'; DraftMax = 2; DraftPMin = 0.0 } })
        }
        @{
            Name = 'vulkan-256k'; Tool = 'cli'
            BuildKeys = @('R4QsaUnionVulkan'); ModelKeys = @('UnslothPle16')
            Environment = @{
                GGML_VK_MOE_LEGACY_TILE_SELECTION = '1'
                GGML_VK_GET_ROWS_128X4 = '0'
                GGML_VK_QSA_UNION = '1'
                LLAMA_MTP_DIAG = 'wall'
            }
            Cases = @(@{ Name = '256k'; Parameters = @{ Context = 262144; InputKey = '256k' } })
            Variants = @(
                @{ Name = 'on-wall'; Parameters = @{ Mtp = $true; DraftModelKey = 'UnslothMtp'; DraftMax = 2; DraftPMin = 0.0 } }
                @{ Name = 'off-wall'; Parameters = @{} }
            )
        }
    )
}
