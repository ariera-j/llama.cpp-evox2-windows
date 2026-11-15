@{
    SchemaVersion = 1
    Name = 'qwen38-r6-s5-mtp-dense'

    # S5 MTP-DENSE-001 only: same-binary OFF/ON, MTP enabled in both arms.
    # Run Windows build, policy/state tests, and 4k smoke before this matrix.
    # Sequence: IQ3 Vulkan 64k -> 128k, IQ3 ROCm 64k -> 128k,
    # then FP4-FAST Vulkan 64k. Do not execute the whole matrix at once.
    # Required local.psd1 keys: S5Vulkan, S5ROCm, UnslothPle16,
    # UnslothMtp, AgentionRocmFp4FastPle16,
    # AgentionRocmFp4FastMtp, Inputs.64k, Inputs.128k.
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
            LLAMA_MTP_SKIP_DENSE_INDEXER     = '0'
            GGML_VK_QSA_UNION                 = '0'
            GGML_VK_QSA_UNION_MIN_KV          = '32768'
            GGML_VK_QSA_UNION_STATS           = $null
            GGML_VK_QSA_UNION_STATS_FILE      = $null
            GGML_VK_QSA_UNION_STATS_KV_BIN    = $null
            GGML_VK_FA_SPARSE_DISABLE        = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION = $null
            LLAMA_MTP_QSA_MIN_KV             = $null
            LLAMA_MTP_DIAG                    = $null
            LLAMA_QSA_NO_POOLED_CACHE        = $null
            LLAMA_QSA_POOLED_MAX_TOKENS      = $null
            LLAMA_GRAPH_REUSE_DISABLE        = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE   = $null
            GGML_VK_FORCE_MMVQ               = $null
            GGML_VK_DISABLE_MMVQ             = $null
            GGML_VK_FUSE_UNARY_MUL           = $null
            GGML_VK_GET_ROWS_128X4           = $null
            QWEN4EXP_QSA_GATHER              = $null
            EVOX2_AB_RUN                     = $null
            EVOX2_ABBA_RUN                   = $null
        }
    }

    Jobs = @(
        @{
            Name = 's5-iq3-vulkan'
            Tool = 'cli'
            BuildKeys = @('S5Vulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '64k';  Parameters = @{ Context = 65536;  InputKey = '64k';  DraftModelKey = 'UnslothMtp' } }
                @{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k'; DraftModelKey = 'UnslothMtp' } }
            )
            Variants = @(
                @{ Name = 'A1-off'; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '0'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1-on';  Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; EVOX2_ABBA_RUN = 'B1' } }
                @{ Name = 'B2-on';  Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; EVOX2_ABBA_RUN = 'B2' } }
                @{ Name = 'A2-off'; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '0'; EVOX2_ABBA_RUN = 'A2' } }
            )
        }
        @{
            Name = 's5-iq3-rocm'
            Tool = 'cli'
            BuildKeys = @('S5ROCm')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '64k';  Parameters = @{ Context = 65536;  InputKey = '64k';  DraftModelKey = 'UnslothMtp' } }
                @{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k'; DraftModelKey = 'UnslothMtp' } }
            )
            Variants = @(
                @{ Name = 'A1-off'; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '0'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1-on';  Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; EVOX2_ABBA_RUN = 'B1' } }
                @{ Name = 'B2-on';  Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; EVOX2_ABBA_RUN = 'B2' } }
                @{ Name = 'A2-off'; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '0'; EVOX2_ABBA_RUN = 'A2' } }
            )
        }
        @{
            Name = 's5-fp4-vulkan'
            Tool = 'cli'
            BuildKeys = @('S5Vulkan')
            ModelKeys = @('AgentionRocmFp4FastPle16')
            Cases = @(
                @{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k'; DraftModelKey = 'AgentionRocmFp4FastMtp' } }
            )
            Variants = @(
                @{ Name = 'A1-off'; Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '0'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1-on';  Environment = @{ LLAMA_MTP_SKIP_DENSE_INDEXER = '1'; EVOX2_ABBA_RUN = 'B1' } }
            )
        }
    )
}
