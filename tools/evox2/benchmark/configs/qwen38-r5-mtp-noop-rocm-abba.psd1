@{
    SchemaVersion = 1
    Name = 'qwen38-r5-mtp-noop-rocm-abba'

    # Same-binary MTP ON / DENSE ON A1-B1-B2-A2, NOOP is the only toggle.
    # ROCm follows Vulkan correctness; do not interpret variable temp0 text as proof of equivalence.
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
            Temperature      = 0.0
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
            LLAMA_MTP_SKIP_DENSE_INDEXER        = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION    = $null
            LLAMA_QSA_NOOP_TRACE               = $null
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
            Name = 'rocm-128k'; Tool = 'cli'
            BuildKeys = @('R5MtpNoopROCm'); ModelKeys = @('UnslothPle16')
            Environment = @{ GGML_VK_QSA_UNION = $null; GGML_VK_QSA_UNION_MIN_KV = $null }
            Cases = @(@{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k' } })
            Variants = @(
                @{ Name = 'A1'; Parameters = @{ Mtp = $true; DraftModelKey = 'UnslothMtp'; DraftMax = 2; DraftPMin = 0.0 }; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'; LLAMA_QSA_NOOP_TRACE = '0'; LLAMA_MTP_DIAG = 'off'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1'; Parameters = @{ Mtp = $true; DraftModelKey = 'UnslothMtp'; DraftMax = 2; DraftPMin = 0.0 }; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_QSA_NOOP_TRACE = '0'; LLAMA_MTP_DIAG = 'off'; EVOX2_ABBA_RUN = 'B1' } }
                @{ Name = 'B2'; Parameters = @{ Mtp = $true; DraftModelKey = 'UnslothMtp'; DraftMax = 2; DraftPMin = 0.0 }; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_QSA_NOOP_TRACE = '0'; LLAMA_MTP_DIAG = 'off'; EVOX2_ABBA_RUN = 'B2' } }
                @{ Name = 'A2'; Parameters = @{ Mtp = $true; DraftModelKey = 'UnslothMtp'; DraftMax = 2; DraftPMin = 0.0 }; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'; LLAMA_QSA_NOOP_TRACE = '0'; LLAMA_MTP_DIAG = 'off'; EVOX2_ABBA_RUN = 'A2' } }
            )
        }
        @{
            Name = 'rocm-64k'; Tool = 'cli'
            BuildKeys = @('R5MtpNoopROCm'); ModelKeys = @('UnslothPle16')
            Environment = @{ GGML_VK_QSA_UNION = $null; GGML_VK_QSA_UNION_MIN_KV = $null }
            Cases = @(@{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k' } })
            Variants = @(
                @{ Name = 'A1'; Parameters = @{ Mtp = $true; DraftModelKey = 'UnslothMtp'; DraftMax = 2; DraftPMin = 0.0 }; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'; LLAMA_QSA_NOOP_TRACE = '0'; LLAMA_MTP_DIAG = 'off'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1'; Parameters = @{ Mtp = $true; DraftModelKey = 'UnslothMtp'; DraftMax = 2; DraftPMin = 0.0 }; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_QSA_NOOP_TRACE = '0'; LLAMA_MTP_DIAG = 'off'; EVOX2_ABBA_RUN = 'B1' } }
                @{ Name = 'B2'; Parameters = @{ Mtp = $true; DraftModelKey = 'UnslothMtp'; DraftMax = 2; DraftPMin = 0.0 }; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_QSA_NOOP_TRACE = '0'; LLAMA_MTP_DIAG = 'off'; EVOX2_ABBA_RUN = 'B2' } }
                @{ Name = 'A2'; Parameters = @{ Mtp = $true; DraftModelKey = 'UnslothMtp'; DraftMax = 2; DraftPMin = 0.0 }; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'; LLAMA_QSA_NOOP_TRACE = '0'; LLAMA_MTP_DIAG = 'off'; EVOX2_ABBA_RUN = 'A2' } }
            )
        }
        @{
            Name = 'rocm-256k'; Tool = 'cli'
            BuildKeys = @('R5MtpNoopROCm'); ModelKeys = @('UnslothPle16')
            Environment = @{ GGML_VK_QSA_UNION = $null; GGML_VK_QSA_UNION_MIN_KV = $null }
            Cases = @(@{ Name = '256k'; Parameters = @{ Context = 262144; InputKey = '256k' } })
            Variants = @(
                @{ Name = 'A1'; Parameters = @{ Mtp = $true; DraftModelKey = 'UnslothMtp'; DraftMax = 2; DraftPMin = 0.0 }; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'; LLAMA_QSA_NOOP_TRACE = '0'; LLAMA_MTP_DIAG = 'off'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1'; Parameters = @{ Mtp = $true; DraftModelKey = 'UnslothMtp'; DraftMax = 2; DraftPMin = 0.0 }; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_QSA_NOOP_TRACE = '0'; LLAMA_MTP_DIAG = 'off'; EVOX2_ABBA_RUN = 'B1' } }
                @{ Name = 'B2'; Parameters = @{ Mtp = $true; DraftModelKey = 'UnslothMtp'; DraftMax = 2; DraftPMin = 0.0 }; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_QSA_NOOP_TRACE = '0'; LLAMA_MTP_DIAG = 'off'; EVOX2_ABBA_RUN = 'B2' } }
                @{ Name = 'A2'; Parameters = @{ Mtp = $true; DraftModelKey = 'UnslothMtp'; DraftMax = 2; DraftPMin = 0.0 }; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'; LLAMA_QSA_NOOP_TRACE = '0'; LLAMA_MTP_DIAG = 'off'; EVOX2_ABBA_RUN = 'A2' } }
            )
        } 
    )
}
