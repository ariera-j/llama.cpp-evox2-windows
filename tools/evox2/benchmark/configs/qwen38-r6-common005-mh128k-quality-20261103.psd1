@{
    SchemaVersion = 1
    Name = 'qwen38-r6-common005-mh128k-quality-20261103'

    # QUALITY ONLY, not a performance ABBA comparison.
    # MH-128K A/B are QUESTION ORDER, not Gather switches.
    # Original frozen prompts/manifests: seeds 20261025 and 20261026.
    # Preconditions: existing b12013 R6RocmCommon005 build; exact GGUFs,
    # validated full-length A/B prompts in local.psd1 Inputs.
    Settings = @{
        CooldownSeconds = 45
        ContinueOnError = $false
    }

    Defaults = @{
        CliParameters = @{
            KvType           = 'f16'
            UBatch           = 512
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
            Fit              = 'on'
            Mtp              = $false
            ResourceMonitor  = $false
            ExtraArgs        = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--top-k', '20', '--min-p', '0.05')
        }
        Environment = @{
            QWEN4EXP_QSA_GATHER              = '0'
            LLAMA_EVOX2_RGP_SSE_TRACE        = '0'
            GGML_VK_QSA_UNION                = '0'
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
        # The ONLY short preflight: confirm ROCmFP4 loads, emits valid
        # 32k answers and activates Gather on the ON arm.
        @{
            Name = 'mh-fp4-gather-preflight'
            Tool = 'cli'
            BuildKeys = @('R6RocmCommon005')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(
                @{ Name = 'fp4-32k'; Parameters = @{ Context = 32768; InputKey = '32k'; GenerationTokens = 64 } }
            )
            Variants = @(
                @{ Name = 'gather-off'; Environment = @{ QWEN4EXP_QSA_GATHER = '0' } }
                @{ Name = 'gather-on';  Environment = @{ QWEN4EXP_QSA_GATHER = '1' } }
            )
        }

        # First run only seed20261025; run seed20261026 after review.
        # A order: OFF -> ON; B order: ON -> OFF (counterbalanced).
        @{
            Name = 'mh-IQ3-A'
            Tool = 'cli'
            BuildKeys = @('R6RocmCommon005')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = 'seed20261025'; Parameters = @{ Context = 131072; InputKey = 'MH128K_S20261025_A' } }
                @{ Name = 'seed20261026'; Parameters = @{ Context = 131072; InputKey = 'MH128K_S20261026_A' } }
            )
            Variants = @(
                @{ Name = 'gather-off'; Environment = @{ QWEN4EXP_QSA_GATHER = '0' } }
                @{ Name = 'gather-on';  Environment = @{ QWEN4EXP_QSA_GATHER = '1' } }
            )
        }
        @{
            Name = 'mh-IQ3-B'
            Tool = 'cli'
            BuildKeys = @('R6RocmCommon005')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = 'seed20261025'; Parameters = @{ Context = 131072; InputKey = 'MH128K_S20261025_B' } }
                @{ Name = 'seed20261026'; Parameters = @{ Context = 131072; InputKey = 'MH128K_S20261026_B' } }
            )
            Variants = @(
                @{ Name = 'gather-on';  Environment = @{ QWEN4EXP_QSA_GATHER = '1' } }
                @{ Name = 'gather-off'; Environment = @{ QWEN4EXP_QSA_GATHER = '0' } }
            )
        }
        @{
            Name = 'mh-FP4-A'
            Tool = 'cli'
            BuildKeys = @('R6RocmCommon005')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(
                @{ Name = 'seed20261025'; Parameters = @{ Context = 131072; InputKey = 'MH128K_S20261025_A' } }
                @{ Name = 'seed20261026'; Parameters = @{ Context = 131072; InputKey = 'MH128K_S20261026_A' } }
            )
            Variants = @(
                @{ Name = 'gather-off'; Environment = @{ QWEN4EXP_QSA_GATHER = '0' } }
                @{ Name = 'gather-on';  Environment = @{ QWEN4EXP_QSA_GATHER = '1' } }
            )
        }
        @{
            Name = 'mh-FP4-B'
            Tool = 'cli'
            BuildKeys = @('R6RocmCommon005')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(
                @{ Name = 'seed20261025'; Parameters = @{ Context = 131072; InputKey = 'MH128K_S20261025_B' } }
                @{ Name = 'seed20261026'; Parameters = @{ Context = 131072; InputKey = 'MH128K_S20261026_B' } }
            )
            Variants = @(
                @{ Name = 'gather-on';  Environment = @{ QWEN4EXP_QSA_GATHER = '1' } }
                @{ Name = 'gather-off'; Environment = @{ QWEN4EXP_QSA_GATHER = '0' } }
            )
        }
    )
}
