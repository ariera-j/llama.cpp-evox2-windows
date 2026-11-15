@{
    SchemaVersion = 1
    Name = 'qwen38-r6-s9-gapfill-overnight-20261029'

    # Exactly 21 sequential CLI runs. No implicit repetitions or retries.
    # Keep 256k MTP runs last because they have the highest resource risk.
    # Vulkan ON enables five switches; ROCm ON enables DENSE/NOOP only.
    # With MTP OFF, MTP-specific switches may have no runtime effect.
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
            GenerationTokens        = 1024
            PromptCacheMiB          = 0
            Temperature             = 0.2
            TopP                    = 0.8
            Reasoning               = 'off'
            Fit                     = 'off'
            Mtp                     = $false
            ResourceMonitor         = $true
            ResourceIntervalSeconds = 2
            ProgressIntervalSeconds = 15
            ExtraArgs               = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234')
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
            Name = 'gap-original-vulkan-64k'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('UnslothOriginal')
            Cases = @(
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k' } }
            )
            Variants = @(
                @{ Name = 'A-all-off' }
                @{ Name = 'B-all-on'; Environment = @{
                    GGML_VK_QSA_UNION = '1'
                    LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
                    LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
                    LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'
                    LLAMA_MTP_EH_PROJ_FLATTEN = '1'
                } }
            )
        }
        @{
            Name = 'gap-original-rocm-64k'
            Tool = 'cli'
            BuildKeys = @('CombinedROCm')
            ModelKeys = @('UnslothOriginal')
            Cases = @(
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k' } }
            )
            Variants = @(
                @{ Name = 'A-all-off' }
                @{ Name = 'B-rocm-dense-noop-on'; Environment = @{
                    LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
                    LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
                } }
            )
        }
        @{
            Name = 'gap-ple16-nomtp-vulkan'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '64k';  Parameters = @{ Context = 65536;  InputKey = '64k' } }
                @{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k' } }
            )
            Variants = @(
                @{ Name = 'A-all-off' }
                @{ Name = 'B-all-on'; Environment = @{
                    GGML_VK_QSA_UNION = '1'
                    LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
                    LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
                    LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'
                    LLAMA_MTP_EH_PROJ_FLATTEN = '1'
                } }
            )
        }
        @{
            Name = 'gap-ple16-nomtp-rocm'
            Tool = 'cli'
            BuildKeys = @('CombinedROCm')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '64k';  Parameters = @{ Context = 65536;  InputKey = '64k' } }
                @{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k' } }
            )
            Variants = @(
                @{ Name = 'A-all-off' }
                @{ Name = 'B-rocm-dense-noop-on'; Environment = @{
                    LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
                    LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
                } }
            )
        }
        @{
            Name = 'gap-fp4-nomtp-vulkan'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(
                @{ Name = '64k';  Parameters = @{ Context = 65536;  InputKey = '64k' } }
                @{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k' } }
            )
            Variants = @(
                @{ Name = 'A-all-off' }
                @{ Name = 'B-all-on'; Environment = @{
                    GGML_VK_QSA_UNION = '1'
                    LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
                    LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
                    LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'
                    LLAMA_MTP_EH_PROJ_FLATTEN = '1'
                } }
            )
        }
        @{
            Name = 'gap-iq4-nomtp-vulkan-64k'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('UnslothIQ4XSPle16')
            Parameters = @{
                UBatch = 512
                GenerationTokens = 256
                Fit = 'on'
            }
            Cases = @(
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k' } }
            )
            Variants = @(
                @{ Name = 'B-all-on'; Environment = @{
                    GGML_VK_QSA_UNION = '1'
                    LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
                    LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
                    LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'
                    LLAMA_MTP_EH_PROJ_FLATTEN = '1'
                } }
            )
        }
        @{
            Name = 'gap-huihui-nomtp-vulkan-64k'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('HuihuiIQ4XSPle16')
            Parameters = @{
                UBatch = 512
                GenerationTokens = 256
                Fit = 'on'
            }
            Cases = @(
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k' } }
            )
            Variants = @(
                @{ Name = 'B-all-on'; Environment = @{
                    GGML_VK_QSA_UNION = '1'
                    LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
                    LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
                    LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'
                    LLAMA_MTP_EH_PROJ_FLATTEN = '1'
                } }
            )
        }
        @{
            Name = 'gap-ple16-mtp-vulkan-256k'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('UnslothPle16')
            Parameters = @{
                Mtp = $true
                DraftMax = 2
                DraftPMin = 0.0
                GenerationTokens = 512
                Temperature = 0.0
                ExtraArgs = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--ignore-eos')
            }
            Cases = @(
                @{ Name = '256k'; Parameters = @{ Context = 262144; InputKey = '256k'; DraftModelKey = 'UnslothMtp' } }
            )
            Variants = @(
                @{ Name = 'A-all-off' }
            )
        }
        @{
            Name = 'gap-ple16-mtp-rocm-256k'
            Tool = 'cli'
            BuildKeys = @('CombinedROCm')
            ModelKeys = @('UnslothPle16')
            Parameters = @{
                Mtp = $true
                DraftMax = 2
                DraftPMin = 0.0
                GenerationTokens = 512
                Temperature = 0.0
                ExtraArgs = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--ignore-eos')
            }
            Cases = @(
                @{ Name = '256k'; Parameters = @{ Context = 262144; InputKey = '256k'; DraftModelKey = 'UnslothMtp' } }
            )
            Variants = @(
                @{ Name = 'A-all-off' }
                @{ Name = 'B-rocm-dense-noop-on'; Environment = @{
                    LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
                    LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
                } }
            )
        }
    )
}
