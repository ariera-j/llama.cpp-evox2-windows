@{
    SchemaVersion = 1
    Name = 'qwen38-r5-qsa-union-batch'

    # Single unattended 12-run matrix: 128k pair -> 256k pair -> 64k ABBA.
    # PLE16 A/B for longctx; Original and PLE16 ABBA at 64k.
    # Standalone r5 QSA validation gate already passed (18 OFF + 18 ON).
    # Preserve this exact plan for reproducibility and use -PlanOnly first.
    # Do not enable r4 retired MoE/GET_ROWS selection switches.
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

        # Reset inherited experimental overrides and leave retired r4
        # environment variables unset. Stats are NOT ported in Phase B.
        Environment = @{
            GGML_VK_QSA_UNION                  = '0'
            GGML_VK_QSA_UNION_MIN_KV           = $null
            GGML_VK_QSA_UNION_STATS            = $null
            GGML_VK_QSA_UNION_STATS_FILE       = $null
            GGML_VK_QSA_UNION_STATS_KV_BIN     = $null
            GGML_VK_MOE_LEGACY_TILE_SELECTION = $null
            GGML_VK_MOE_TILE_LOG              = $null
            GGML_VK_GET_ROWS_128X4            = $null
            GGML_VK_PERF_GET_ROWS_DETAILS     = $null
            GGML_VK_PERF_LOGGER               = $null
            GGML_VK_PERF_LOGGER_FREQUENCY     = $null
            GGML_VK_PERF_LOGGER_CONCURRENT    = $null
            GGML_VK_FA_SPARSE_DISABLE         = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER      = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION  = $null
            LLAMA_MTP_DIAG                    = $null
            LLAMA_QSA_NO_POOLED_CACHE         = $null
            LLAMA_QSA_POOLED_MAX_TOKENS       = $null
            QWEN4EXP_QSA_GATHER               = $null
            LLAMA_MTP_QSA_MIN_KV              = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE    = $null
            LLAMA_GRAPH_REUSE_DISABLE         = $null
            GGML_VK_FUSE_UNARY_MUL            = $null
            GGML_VK_SHMEM_PAD                 = $null
            GGML_VK_DENSE_WAVE32              = $null
            EVOX2_AB_RUN                      = $null
            EVOX2_ABBA_RUN                    = $null
        }
    }


    Jobs = @(
        @{
            Name = 'longctx-pair'
            Tool = 'cli'
            BuildKeys = @('R5QsaUnionVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k' } }
                @{ Name = '256k'; Parameters = @{ Context = 262144; InputKey = '256k' } }
            )
            Variants = @(
                @{ Name = 'A1-off'; Parameters = @{}; Environment = @{ GGML_VK_QSA_UNION = '0'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1-on';  Parameters = @{}; Environment = @{ GGML_VK_QSA_UNION = '1'; EVOX2_ABBA_RUN = 'B1' } }
            )
        }
        @{
            Name = 'normal64k-abba'
            Tool = 'cli'
            BuildKeys = @('R5QsaUnionVulkan')
            ModelKeys = @('UnslothOriginal', 'UnslothPle16')
            Cases = @(
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k' } }
            )
            Variants = @(
                @{ Name = 'A1-off'; Parameters = @{}; Environment = @{ GGML_VK_QSA_UNION = '0'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1-on';  Parameters = @{}; Environment = @{ GGML_VK_QSA_UNION = '1'; EVOX2_ABBA_RUN = 'B1' } }
                @{ Name = 'B2-on';  Parameters = @{}; Environment = @{ GGML_VK_QSA_UNION = '1'; EVOX2_ABBA_RUN = 'B2' } }
                @{ Name = 'A2-off';Parameters = @{}; Environment = @{ GGML_VK_QSA_UNION = '0'; EVOX2_ABBA_RUN = 'A2' } }
            )
        }
    )
}
