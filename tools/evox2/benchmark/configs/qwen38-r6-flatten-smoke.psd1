@{
    SchemaVersion = 1
    Name = 'qwen38-r6-flatten-smoke'

    # C: Stage-B OFF; A: Stage-B ON, flatten OFF; B: Stage-B and flatten ON.
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
            CpuMoe          = 0
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
            LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
            LLAMA_QSA_NOOP_TRACE             = $null
            LLAMA_MTP_DRAFT_PREFILL_KV_CROP  = '0'
            LLAMA_MTP_EH_PROJ_FLATTEN        = '0'
            GGML_VK_QSA_UNION                = '1'
            GGML_VK_QSA_UNION_MIN_KV         = '32768'
            GGML_VK_QSA_UNION_STATS          = $null
            GGML_VK_FA_SPARSE_DISABLE       = $null
            LLAMA_MTP_QSA_MIN_KV            = $null
            LLAMA_MTP_DIAG                   = $null
            LLAMA_QSA_NO_POOLED_CACHE        = $null
            LLAMA_QSA_POOLED_MAX_TOKENS      = $null
            GGML_VK_FORCE_MMVQ               = $null
            GGML_VK_DISABLE_MMVQ             = $null
            GGML_VK_GET_ROWS_128X4           = $null
            QWEN4EXP_QSA_GATHER              = $null
            LLAMA_GRAPH_REUSE_DISABLE       = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE  = $null
            GGML_VK_FUSE_UNARY_MUL          = $null
        }
    }

    Jobs = @(
        @{
            Name = 'flatten-iq3-vulkan-smoke'
            Tool = 'cli'
            BuildKeys = @('FlattenVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '4k'; Parameters = @{ Context = 4096; InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; DraftModelKey = 'UnslothMtp' } }
            )
            Variants = @(
                @{ Name = 'C-stageb-off'; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'; LLAMA_MTP_EH_PROJ_FLATTEN = '0' } }
                @{ Name = 'A-stageb-only'; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '0' } }
                @{ Name = 'B-flatten-on';  Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1' } }
            )
        }
        @{
            Name = 'flatten-fp4-vulkan-smoke'
            Tool = 'cli'
            BuildKeys = @('FlattenVulkan')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(
                @{ Name = '4k'; Parameters = @{ Context = 4096; InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; DraftModelKey = 'AgentionRocmFp4FastMtp' } }
            )
            Variants = @(
                @{ Name = 'C-stageb-off'; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'; LLAMA_MTP_EH_PROJ_FLATTEN = '0' } }
                @{ Name = 'A-stageb-only'; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '0' } }
                @{ Name = 'B-flatten-on';  Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1' } }
            )
        }
    )
}
