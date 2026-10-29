@{
    SchemaVersion = 1
    Name = 'qwen38-r6-s8-vulkan-abba'

    # Same-binary comparison of all five speed flags. Run 64k before 128k.
    # S7-B's transient B1 TG lag requires reporting individual run times.
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
            EVOX2_ABBA_RUN                   = $null
        }
    }

    Jobs = @(
        @{
            Name = 's8-iq3-vulkan-abba'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k'; DraftModelKey = 'UnslothMtp' } }
                @{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k'; DraftModelKey = 'UnslothMtp' } }
            )
            Variants = @(
                @{ Name = 'A1-all-off'; Environment = @{ EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1-all-on';  Environment = @{ EVOX2_ABBA_RUN = 'B1'; GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1' } }
                @{ Name = 'B2-all-on';  Environment = @{ EVOX2_ABBA_RUN = 'B2'; GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1' } }
                @{ Name = 'A2-all-off'; Environment = @{ EVOX2_ABBA_RUN = 'A2' } }
            )
        }
        @{
            Name = 's8-fp4-vulkan-64k-abba'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k'; DraftModelKey = 'AgentionRocmFp4FastMtp' } }
            )
            Variants = @(
                @{ Name = 'A1-all-off'; Environment = @{ EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1-all-on';  Environment = @{ EVOX2_ABBA_RUN = 'B1'; GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1' } }
                @{ Name = 'B2-all-on';  Environment = @{ EVOX2_ABBA_RUN = 'B2'; GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1' } }
                @{ Name = 'A2-all-off'; Environment = @{ EVOX2_ABBA_RUN = 'A2' } }
            )
        }
        @{
            Name = 's8-fp4-vulkan-128k-ab'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(
                @{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k'; DraftModelKey = 'AgentionRocmFp4FastMtp' } }
            )
            Variants = @(
                @{ Name = 'A1-all-off'; Environment = @{ EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1-all-on';  Environment = @{ EVOX2_ABBA_RUN = 'B1'; GGML_VK_QSA_UNION = '1'; LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'; LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1' } }
            )
        }
    )
}
