@{
    SchemaVersion = 1
    Name = 'qwen38-r6-s6-mtp-noop-smoke'

    # Short target smoke with DENSE=1 and QSA union=0 in all arms.
    # LLAMA_QSA_NOOP_TRACE=1 adds per-trim instrumentation: do not use for timing.
    Settings = @{
        CooldownSeconds = 5
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
            GenerationTokens = 64
            PromptCacheMiB   = 0
            Temperature      = 0.0
            TopP             = 0.8
            Reasoning        = 'off'
            Fit              = 'off'
            Mtp              = $true
            DraftMax         = 2
            DraftPMin        = 0.0
            ResourceMonitor  = $true
            ExtraArgs        = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--ignore-eos')
        }
        Environment = @{
            LLAMA_MTP_SKIP_DENSE_INDEXER     = '1'
            LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'
            LLAMA_QSA_NOOP_TRACE             = $null
            GGML_VK_QSA_UNION                = '0'
            GGML_VK_QSA_UNION_STATS          = $null
            GGML_VK_FA_SPARSE_DISABLE       = $null
            LLAMA_MTP_QSA_MIN_KV            = $null
            LLAMA_MTP_DIAG                   = $null
            LLAMA_GRAPH_REUSE_DISABLE       = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE  = $null
            GGML_VK_FUSE_UNARY_MUL          = $null
        }
    }

    Jobs = @(
        @{
            Name = 's6-iq3-smoke'
            Tool = 'cli'
            BuildKeys = @('S6Vulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '4k'; Parameters = @{ Context = 4096; InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; DraftModelKey = 'UnslothMtp' } }
            )
            Variants = @(
                @{ Name = 'A-off';   Environment = @{ LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0' } }
                @{ Name = 'B-on';    Environment = @{ LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1' } }
                @{ Name = 'A-trace'; Environment = @{ LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'; LLAMA_QSA_NOOP_TRACE = '1' } }
                @{ Name = 'B-trace'; Environment = @{ LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_QSA_NOOP_TRACE = '1' } }
            )
        }
        @{
            Name = 's6-fp4-smoke'
            Tool = 'cli'
            BuildKeys = @('S6Vulkan')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(
                @{ Name = '4k'; Parameters = @{ Context = 4096; InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; DraftModelKey = 'AgentionRocmFp4FastMtp' } }
            )
            Variants = @(
                @{ Name = 'A-off'; Environment = @{ LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0' } }
                @{ Name = 'B-on';  Environment = @{ LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1' } }
            )
        }
        @{
            Name = 's6-iq3-rocm-smoke'
            Tool = 'cli'
            BuildKeys = @('S6ROCm')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '4k'; Parameters = @{ Context = 4096; InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; DraftModelKey = 'UnslothMtp' } }
            )
            Variants = @(
                @{ Name = 'A-off'; Environment = @{ LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0' } }
                @{ Name = 'B-on';  Environment = @{ LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1' } }
            )
        }
    )
}
