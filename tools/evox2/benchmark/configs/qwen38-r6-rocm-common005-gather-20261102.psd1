@{
    SchemaVersion = 1
    Name = 'qwen38-r6-rocm-common005-gather-20261102'

    # COMMON-005 r6 prototype: separate patched binary, identical ON/OFF.
    # Mandatory order: 4k fallback smoke, 32k activation+output gate,
    # then 64k -> 128k -> 256k (ABBA per depth).
    # NEVER launch unsafe broad ROCm FLASH_ATTN_EXT backend tests on gfx1151.
    Settings = @{
        CooldownSeconds = 60
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
            ResourceMonitor  = $false
            ExtraArgs        = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--ignore-eos')
        }
        Environment = @{
            QWEN4EXP_QSA_GATHER              = '0'
            LLAMA_EVOX2_RGP_SSE_TRACE        = '0'
            GGML_VK_QSA_UNION                = '0'
            GGML_VK_QSA_UNION_MIN_KV         = '32768'
            GGML_VK_QSA_UNION_STATS          = $null
            GGML_VK_QSA_UNION_STATS_FILE     = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER     = '0'
            LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'
            LLAMA_MTP_DRAFT_PREFILL_KV_CROP  = '0'
            LLAMA_MTP_EH_PROJ_FLATTEN        = '0'
            LLAMA_QSA_NO_POOLED_CACHE        = $null
            LLAMA_QSA_POOLED_MAX_TOKENS      = $null
            LLAMA_GRAPH_REUSE_DISABLE        = $null
            EVOX2_ABBA_RUN                   = $null
        }
    }

    Jobs = @(
        @{
            Name = 'common005-fallback-smoke'
            Tool = 'cli'
            BuildKeys = @('R6RocmCommon005')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '4k'; Parameters = @{ Context = 4096; InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; GenerationTokens = 64 } }
            )
            Variants = @(
                @{ Name = 'A-off'; Environment = @{ QWEN4EXP_QSA_GATHER = '0' } }
                @{ Name = 'B-on';  Environment = @{ QWEN4EXP_QSA_GATHER = '1' } }
            )
        }
        @{
            Name = 'common005-activation-32k'
            Tool = 'cli'
            BuildKeys = @('R6RocmCommon005')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '32k'; Parameters = @{ Context = 32768; InputKey = '32k'; GenerationTokens = 64 } }
            )
            Variants = @(
                @{ Name = 'A-off'; Environment = @{ QWEN4EXP_QSA_GATHER = '0' } }
                @{ Name = 'B-on';  Environment = @{ QWEN4EXP_QSA_GATHER = '1' } }
            )
        }
        @{
            Name = 'common005-long-abba'
            Tool = 'cli'
            BuildKeys = @('R6RocmCommon005')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '64k';  Parameters = @{ Context = 65536;  InputKey = '64k'  } }
                @{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k' } }
                @{ Name = '256k'; Parameters = @{ Context = 262144; InputKey = '256k' } }
            )
            Variants = @(
                @{ Name = 'A1-off'; Environment = @{ EVOX2_ABBA_RUN = 'A1'; QWEN4EXP_QSA_GATHER = '0' } }
                @{ Name = 'B1-on';  Environment = @{ EVOX2_ABBA_RUN = 'B1'; QWEN4EXP_QSA_GATHER = '1' } }
                @{ Name = 'B2-on';  Environment = @{ EVOX2_ABBA_RUN = 'B2'; QWEN4EXP_QSA_GATHER = '1' } }
                @{ Name = 'A2-off'; Environment = @{ EVOX2_ABBA_RUN = 'A2'; QWEN4EXP_QSA_GATHER = '0' } }
            )
        }
    )
}
