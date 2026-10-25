@{
    SchemaVersion = 1
    Name = 'qwen38-r6-s3-mtp-native'

    # S3 compatibility gate only. Run 4k smoke with Measure-LlamaCli.ps1 first.
    # Reuse the validated S2Vulkan b11882 binary for the *unpatched* native gate.
    # After any source fix, copy this plan with BuildKeys changed to the new S3Vulkan
    # build so MTP OFF and ON are compared using exactly the same executable.
    # Required local.psd1 keys: S2Vulkan, UnslothPle16, UnslothMtp,
    # AgentionRocmFp4FastPle16, AgentionRocmFp4FastMtp, Inputs.32k/64k.
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
            Temperature      = 0.2
            TopP             = 0.8
            Reasoning        = 'off'
            Fit              = 'off'
            Mtp              = $false
            DraftMax         = 2
            DraftPMin        = 0.0
            ResourceMonitor  = $true
            ExtraArgs        = @('-tb', '4', '--ctx-checkpoints', '0t')
        }
        Environment = @{
            GGML_VK_FORCE_MMVQ                = $null
            GGML_VK_DISABLE_MMVQ              = $null
            GGML_VK_QSA_UNION                 = $null
            GGML_VK_QSA_UNION_MIN_KV          = $null
            GGML_VK_QSA_UNION_STATS           = $null
            GGML_VK_QSA_UNION_STATS_FILE      = $null
            GGML_VK_QSA_UNION_STATS_KV_BIN    = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER     = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION = $null
            LLAMA_MTP_DIAG                    = $null
            LLAMA_MTP_QSA_MIN_KV              = $null
            LLAMA_QSA_NO_POOLED_CACHE        = $null
            LLAMA_QSA_POOLED_MAX_TOKENS      = $null
            QWEN4EXP_QSA_GATHER              = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE   = $null
            LLAMA_GRAPH_REUSE_DISABLE        = $null
            GGML_VK_FUSE_UNARY_MUL           = $null
            GGML_VK_GET_ROWS_128X4           = $null
            EVOX2_AB_RUN                     = $null
            EVOX2_ABBA_RUN                   = $null
        }
    }

    Jobs = @(
        @{
            Name = 's3-iq3-ple16'
            Tool = 'cli'
            BuildKeys = @('S2Vulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '32k'; Parameters = @{ Context = 32768; InputKey = '32k'; GenerationTokens = 256 } }
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k'; GenerationTokens = 512 } }
            )
            Variants = @(
                @{ Name = 'off'; Parameters = @{ Mtp = $false; DraftModelKey = '' } }
                @{ Name = 'on';  Parameters = @{ Mtp = $true; DraftModelKey = 'UnslothMtp'; DraftMax = 2; DraftPMin = 0.0 } }
            )
        }
        @{
            Name = 's3-rocmfp4-fast-ple16'
            Tool = 'cli'
            BuildKeys = @('S2Vulkan')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(
                @{ Name = '32k'; Parameters = @{ Context = 32768; InputKey = '32k'; GenerationTokens = 256 } }
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k'; GenerationTokens = 512 } }
            )
            Variants = @(
                @{ Name = 'off'; Parameters = @{ Mtp = $false; DraftModelKey = '' } }
                @{ Name = 'on';  Parameters = @{ Mtp = $true; DraftModelKey = 'AgentionRocmFp4FastMtp'; DraftMax = 2; DraftPMin = 0.0 } }
            )
        }
    )
}
