@{
    SchemaVersion = 1
    Name = 'qwen38-r6-s9-final-models'

    # S9 final-model smoke / real input only, NOT a speed-patch ABBA.
    # Run ONE -OnlyJob / -OnlyCase at a time: 4k -> 16k -> 64k -> selected 128k.
    # 4k/16k short input is NOT a full-context prompt. MTP and all five S8
    # performance switches remain OFF for unvalidated IQ4/huihui models.
    # Requires ignored local.psd1 model keys UnslothIQ4XSPle16 and
    # HuihuiIQ4XSPle16, CombinedVulkan, Inputs.'64k'/'128k'.

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
            GenerationTokens        = 256
            PromptCacheMiB          = 0
            Temperature             = 0.2
            TopP                    = 0.8
            Reasoning               = 'off'
            Fit                     = 'on'
            Mtp                     = $false
            ResourceMonitor         = $true
            ResourceIntervalSeconds = 2
            ProgressIntervalSeconds = 15
            ExtraArgs               = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234')
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
            Name = 's9-unsloth-iq4xs-vulkan'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('UnslothIQ4XSPle16')
            Cases = @(
                @{ Name = '4k';   Parameters = @{ Context = 4096;   InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; GenerationTokens = 64 } }
                @{ Name = '16k';  Parameters = @{ Context = 16384;  InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; GenerationTokens = 64 } }
                @{ Name = '64k';  Parameters = @{ Context = 65536;  InputKey = '64k';  GenerationTokens = 256 } }
                @{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k'; GenerationTokens = 256 } }
            )
            Variants = @(@{ Name = 's9-stock-nomtp' })
        }
        @{
            Name = 's9-huihui-iq4xs-vulkan'
            Tool = 'cli'
            BuildKeys = @('CombinedVulkan')
            ModelKeys = @('HuihuiIQ4XSPle16')
            Cases = @(
                @{ Name = '4k';   Parameters = @{ Context = 4096;   InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; GenerationTokens = 64 } }
                @{ Name = '16k';  Parameters = @{ Context = 16384;  InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; GenerationTokens = 64 } }
                @{ Name = '64k';  Parameters = @{ Context = 65536;  InputKey = '64k';  GenerationTokens = 256 } }
                @{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k'; GenerationTokens = 256 } }
            )
            Variants = @(@{ Name = 's9-stock-nomtp' })
        }
    )
}
