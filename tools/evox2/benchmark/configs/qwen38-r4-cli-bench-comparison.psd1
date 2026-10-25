@{
    SchemaVersion = 1
    Name = 'qwen38-r4-cli-bench-comparison'
    # MTP OFF only: pinned llama-bench has no MTP/speculative execution path.
    # Select -OnlyCase 64k first; review fresh CLI token counts before bench.
    # Six invocations per case: two CLI, two full PP, two depth-filled TG.
    # PP repeats2 + full-prompt warmup; TG repeats3 with depth state reuse.
    Settings = @{ CooldownSeconds = 10; ContinueOnError = $false }
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
        BenchParameters = @{
            KvType = 'f16'; UBatch = 1024; Batch = 2048; Threads = 4
            GpuLayers = 999; CpuMoe = 0; FlashAttn = 'auto'
            ResourceMonitor = $true; ExtraArgs = @('-v')
            # Keep standard warmup; PP warmup evaluates the entire prompt.
            NoWarmup = $false
        }
        Environment = @{
            LLAMA_MTP_SKIP_DENSE_INDEXER        = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION    = $null
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
            Name = 'vulkan-cli'; Tool = 'cli'
            BuildKeys = @('R4QsaUnionVulkan'); ModelKeys = @('UnslothPle16')
            Environment = @{ GGML_VK_MOE_LEGACY_TILE_SELECTION = '1'; GGML_VK_GET_ROWS_128X4 = '0'; GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DIAG = 'off' }
            Cases = @(
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k' } }
                @{ Name = '256k'; Parameters = @{ Context = 262144; InputKey = '256k' } }
            )
        }
        @{
            Name = 'rocm-cli'; Tool = 'cli'
            BuildKeys = @('R4ROCm'); ModelKeys = @('UnslothPle16')
            Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DIAG = 'off' }
            Cases = @(
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k' } }
                @{ Name = '256k'; Parameters = @{ Context = 262144; InputKey = '256k' } }
            )
        }
        @{
            Name = 'vulkan-pp'; Tool = 'bench'
            BuildKeys = @('R4QsaUnionVulkan'); ModelKeys = @('UnslothPle16')
            Environment = @{ GGML_VK_MOE_LEGACY_TILE_SELECTION = '1'; GGML_VK_GET_ROWS_128X4 = '0'; GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DIAG = 'off' }
            Cases = @(
                @{ Name = '64k'; Parameters = @{ PromptTokens = @(61789); GenerationTokens = @(0); Depths = @(0); Repetitions = 2 } }
                @{ Name = '256k'; Parameters = @{ PromptTokens = @(255181); GenerationTokens = @(0); Depths = @(0); Repetitions = 2 } }
            )
        }
        @{
            Name = 'rocm-pp'; Tool = 'bench'
            BuildKeys = @('R4ROCm'); ModelKeys = @('UnslothPle16')
            Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DIAG = 'off' }
            Cases = @(
                @{ Name = '64k'; Parameters = @{ PromptTokens = @(61789); GenerationTokens = @(0); Depths = @(0); Repetitions = 2 } }
                @{ Name = '256k'; Parameters = @{ PromptTokens = @(255181); GenerationTokens = @(0); Depths = @(0); Repetitions = 2 } }
            )
        }
        @{
            Name = 'vulkan-tg'; Tool = 'bench'
            BuildKeys = @('R4QsaUnionVulkan'); ModelKeys = @('UnslothPle16')
            Environment = @{ GGML_VK_MOE_LEGACY_TILE_SELECTION = '1'; GGML_VK_GET_ROWS_128X4 = '0'; GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DIAG = 'off' }
            Cases = @(
                @{ Name = '64k'; Parameters = @{ PromptTokens = @(0); GenerationTokens = @(512); Depths = @(61789); Repetitions = 3 } }
                @{ Name = '256k'; Parameters = @{ PromptTokens = @(0); GenerationTokens = @(512); Depths = @(255181); Repetitions = 3 } }
            )
        }
        @{
            Name = 'rocm-tg'; Tool = 'bench'
            BuildKeys = @('R4ROCm'); ModelKeys = @('UnslothPle16')
            Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DIAG = 'off' }
            Cases = @(
                @{ Name = '64k'; Parameters = @{ PromptTokens = @(0); GenerationTokens = @(512); Depths = @(61789); Repetitions = 3 } }
                @{ Name = '256k'; Parameters = @{ PromptTokens = @(0); GenerationTokens = @(512); Depths = @(255181); Repetitions = 3 } }
            )
        }
    )
}
