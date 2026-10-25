@{
    SchemaVersion = 1
    Name = 'qwen38-r6-s4-qsa-union'

    # Isolated S4 speed gate on the exact same Vulkan binary.
    # Run 4k OFF smoke and the 64k ON active-path smoke separately first.
    # IQ3: 64k ABBA -> 128k ABBA; FP4: representative 64/128k A/B.
    # Expected local.psd1 keys: S4Vulkan, UnslothPle16,
    # AgentionRocmFp4FastPle16, Inputs.64k, Inputs.128k.
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
            ResourceMonitor  = $true
            ExtraArgs        = @('-tb', '4', '--ctx-checkpoints', '0t')
        }
        Environment = @{
            GGML_VK_QSA_UNION                 = '0'
            GGML_VK_QSA_UNION_MIN_KV          = '32768'
            GGML_VK_QSA_UNION_STATS           = $null
            GGML_VK_QSA_UNION_STATS_FILE      = $null
            GGML_VK_QSA_UNION_STATS_KV_BIN    = $null
            GGML_VK_FA_SPARSE_DISABLE        = $null
            GGML_VK_FORCE_MMVQ               = $null
            GGML_VK_DISABLE_MMVQ             = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE   = $null
            LLAMA_GRAPH_REUSE_DISABLE        = $null
            GGML_VK_FUSE_UNARY_MUL           = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER     = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION = $null
            LLAMA_MTP_QSA_MIN_KV             = $null
            LLAMA_QSA_NO_POOLED_CACHE        = $null
            LLAMA_QSA_POOLED_MAX_TOKENS      = $null
            QWEN4EXP_QSA_GATHER              = $null
            EVOX2_AB_RUN                     = $null
            EVOX2_ABBA_RUN                   = $null
        }
    }

    Jobs = @(
        @{
            Name = 's4-iq3-ple16'
            Tool = 'cli'
            BuildKeys = @('S4Vulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '64k';  Parameters = @{ Context = 65536;  InputKey = '64k' } }
                @{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k' } }
            )
            Variants = @(
                @{ Name = 'A1-off'; Environment = @{ GGML_VK_QSA_UNION = '0'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1-on';  Environment = @{ GGML_VK_QSA_UNION = '1'; EVOX2_ABBA_RUN = 'B1' } }
                @{ Name = 'B2-on';  Environment = @{ GGML_VK_QSA_UNION = '1'; EVOX2_ABBA_RUN = 'B2' } }
                @{ Name = 'A2-off'; Environment = @{ GGML_VK_QSA_UNION = '0'; EVOX2_ABBA_RUN = 'A2' } }
            )
        }
        @{
            Name = 's4-rocmfp4-fast-ple16'
            Tool = 'cli'
            BuildKeys = @('S4Vulkan')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(
                @{ Name = '64k';  Parameters = @{ Context = 65536;  InputKey = '64k' } }
                @{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k' } }
            )
            Variants = @(
                @{ Name = 'A1-off'; Environment = @{ GGML_VK_QSA_UNION = '0'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1-on';  Environment = @{ GGML_VK_QSA_UNION = '1'; EVOX2_ABBA_RUN = 'B1' } }
            )
        }
    )
}
