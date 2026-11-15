@{
    SchemaVersion = 1
    Name = 'qwen38-r6-s9-rocm-all5-on-manual-64k-20261029'

    # Separate MANUAL check after the 21-run gap-fill matrix.
    # Do not include this plan in the unattended matrix.
    # Vulkan QSA union is not a ROCm kernel feature; the other four flags
    # are deliberately requested, including unqualified Stage-B/flatten.
    Settings = @{
        CooldownSeconds = 30
        ContinueOnError = $false
    }

    Defaults = @{
        CliParameters = @{
            AllocationOnly          = $false
            KvType                  = 'f16'
            UBatch                  = 1024
            Batch                   = 2048
            Threads                 = 4
            GpuLayers               = 999
            CpuMoe                  = 0
            FlashAttn               = 'auto'
            Verbosity               = 4
            GenerationTokens        = 512
            PromptCacheMiB          = 0
            Temperature             = 0.0
            TopP                    = 0.8
            Reasoning               = 'off'
            Fit                     = 'off'
            Mtp                     = $true
            DraftMax                = 2
            DraftPMin               = 0.0
            ResourceMonitor         = $true
            ResourceIntervalSeconds = 2
            ProgressIntervalSeconds = 15
            ExtraArgs               = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--ignore-eos')
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
            LLAMA_MTP_DIAG                   = $null
            LLAMA_QSA_NOOP_TRACE             = $null
            LLAMA_MTP_QSA_MIN_KV             = $null
            LLAMA_QSA_NO_POOLED_CACHE        = $null
            LLAMA_QSA_POOLED_MAX_TOKENS      = $null
            GGML_VK_FA_SPARSE_DISABLE        = $null
            GGML_VK_FORCE_MMVQ               = $null
            GGML_VK_DISABLE_MMVQ             = $null
            GGML_VK_GET_ROWS_128X4           = $null
            QWEN4EXP_QSA_GATHER              = $null
            LLAMA_GRAPH_REUSE_DISABLE       = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE   = $null
            GGML_VK_FUSE_UNARY_MUL            = $null
            EVOX2_AB_RUN                     = $null
            EVOX2_ABBA_RUN                   = $null
        }
    }

    Jobs = @(
        @{
            Name = 'manual-rocm-iq3-ple16-mtp-all5-on'
            Tool = 'cli'
            BuildKeys = @('CombinedROCm')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k'; DraftModelKey = 'UnslothMtp' } }
            )
            Variants = @(
                @{ Name = 'B-all-five-requested-on'; Environment = @{
                    GGML_VK_QSA_UNION                 = '1'
                    LLAMA_MTP_SKIP_DENSE_INDEXER     = '1'
                    LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
                    LLAMA_MTP_DRAFT_PREFILL_KV_CROP  = '1'
                    LLAMA_MTP_EH_PROJ_FLATTEN        = '1'
                } }
            )
        }
    )
}
