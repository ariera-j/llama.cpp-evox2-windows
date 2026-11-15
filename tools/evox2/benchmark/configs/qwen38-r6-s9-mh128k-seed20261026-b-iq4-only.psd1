@{
    SchemaVersion = 1
    Name = 'qwen38-r6-s9-mh128k-seed20261026-b-iq4-only'

    # G9-3 single follow-up: original Unsloth IQ4 B, one job / one run.
    # Matches original IQ4 A and huihui B's frozen seed/sampler/flags.
    # Only the input question order changes compared with original IQ4 A.
    # Requires ignored local.psd1 keys: Builds.CombinedVulkan,
    # Models.UnslothIQ4XSPle16, Inputs.MH128K_20261026_B.

    Settings = @{
        CooldownSeconds = 15
        ContinueOnError = $false
    }

    Defaults = @{
        CliParameters = @{
            AllocationOnly          = $false
            KvType                  = 'f16'
            UBatch                  = 512
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
            Fit                     = 'on'
            Mtp                     = $false
            ResourceMonitor         = $true
            ResourceIntervalSeconds = 2
            ProgressIntervalSeconds = 15
            ExtraArgs               = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--top-k', '20', '--min-p', '0.05')
        }
        Environment = @{
            GGML_VK_QSA_UNION                 = '0'
            GGML_VK_QSA_UNION_MIN_KV          = $null
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
            GGML_VK_FORCE_MMVQ               = $null
            GGML_VK_DISABLE_MMVQ             = $null
            GGML_VK_FA_SPARSE_DISABLE        = $null
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
            Name = 's9-mh-IQ4-B'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('UnslothIQ4XSPle16')
            Cases = @(@{
                Name = 'mh-seed20261026-b'
                Parameters = @{ Context = 131072; InputKey = 'MH128K_20261026_B' }
            })
            Variants = @(@{ Name = 's9-mh-b-nomtp' })
        }
    )
}
