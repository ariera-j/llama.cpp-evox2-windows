@{
    SchemaVersion = 1
    Name = 'qwen38-r6-s8-smoke'

    # Start with 4k. Run 16k and DraftMax=7 only after the initial gate passes.
    # Use -OnlyJob to separate Vulkan, ROCm, and DraftMax=7 checks.
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
            GGML_VK_QSA_UNION                 = '0'
            GGML_VK_QSA_UNION_MIN_KV          = '32768'
            GGML_VK_QSA_UNION_STATS           = $null
            GGML_VK_QSA_UNION_STATS_FILE      = $null
            GGML_VK_QSA_UNION_STATS_KV_BIN    = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER     = '0'
            LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'
            LLAMA_MTP_DRAFT_PREFILL_KV_CROP  = '0'
            LLAMA_MTP_EH_PROJ_FLATTEN        = '0'
            LLAMA_QSA_NOOP_TRACE             = $null
            LLAMA_MTP_DIAG                   = $null
            LLAMA_MTP_QSA_MIN_KV             = $null
            LLAMA_QSA_NO_POOLED_CACHE        = $null
            LLAMA_QSA_POOLED_MAX_TOKENS      = $null
            GGML_VK_FA_SPARSE_DISABLE        = $null
            GGML_VK_FORCE_MMVQ               = $null
            GGML_VK_DISABLE_MMVQ             = $null
            GGML_VK_GET_ROWS_128X4           = $null
            QWEN4EXP_QSA_GATHER              = $null
            LLAMA_GRAPH_REUSE_DISABLE        = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE   = $null
            GGML_VK_FUSE_UNARY_MUL           = $null
        }
    }

    Jobs = @(
        @{
            Name = 's8-iq3-vulkan-smoke'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '4k';  Parameters = @{ Context = 4096;  InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; DraftModelKey = 'UnslothMtp' } }
                @{ Name = '16k'; Parameters = @{ Context = 16384; InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; DraftModelKey = 'UnslothMtp' } }
            )
            Variants = @(
                @{ Name = 'O-nomtp'; Parameters = @{ Mtp = $false; DraftModelKey = '' } }
                @{ Name = 'A-mtp-all-off' }
                @{ Name = 'C-stageb-off'; Environment = @{ GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1' } }
                @{ Name = 'D-stageb-on';  Environment = @{ GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1' } }
                @{ Name = 'E-flatten-on'; Environment = @{ GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1' } }
            )
        }
        @{
            Name = 's8-fp4-vulkan-smoke'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(
                @{ Name = '4k';  Parameters = @{ Context = 4096;  InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; DraftModelKey = 'AgentionRocmFp4FastMtp' } }
                @{ Name = '16k'; Parameters = @{ Context = 16384; InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; DraftModelKey = 'AgentionRocmFp4FastMtp' } }
            )
            Variants = @(
                @{ Name = 'O-nomtp'; Parameters = @{ Mtp = $false; DraftModelKey = '' } }
                @{ Name = 'A-mtp-all-off' }
                @{ Name = 'C-stageb-off'; Environment = @{ GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1' } }
                @{ Name = 'D-stageb-on';  Environment = @{ GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1' } }
                @{ Name = 'E-flatten-on'; Environment = @{ GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1' } }
            )
        }
        @{
            Name = 's8-iq3-vulkan-32k'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '32k'; Parameters = @{ Context = 32768; InputKey = '32k'; DraftModelKey = 'UnslothMtp'; GenerationTokens = 256 } }
            )
            Variants = @(
                @{ Name = 'A-all-off' }
                @{ Name = 'B-all-on'; Environment = @{ GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1' } }
            )
        }
        @{
            Name = 's8-fp4-vulkan-32k'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(
                @{ Name = '32k'; Parameters = @{ Context = 32768; InputKey = '32k'; DraftModelKey = 'AgentionRocmFp4FastMtp'; GenerationTokens = 256 } }
            )
            Variants = @(
                @{ Name = 'A-all-off' }
                @{ Name = 'B-all-on'; Environment = @{ GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1' } }
            )
        }
        @{
            Name = 's8-iq3-rocm-smoke'
            Tool = 'cli'
            BuildKeys = @('CombinedROCm')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '4k'; Parameters = @{ Context = 4096; InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; DraftModelKey = 'UnslothMtp' } }
            )
            Variants = @(
                @{ Name = 'O-nomtp'; Parameters = @{ Mtp = $false; DraftModelKey = '' } }
                @{ Name = 'A-mtp-all-off' }
                @{ Name = 'B-dense-noop-on'; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1' } }
            )
        }
        @{
            Name = 's8-iq3-vulkan-draftmax7'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '4k'; Parameters = @{ Context = 4096; InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; DraftModelKey = 'UnslothMtp'; DraftMax = 7 } }
            )
            Variants = @(
                @{ Name = 'off' }
                @{ Name = 'on'; Environment = @{ GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1' } }
            )
        }
    )
}
