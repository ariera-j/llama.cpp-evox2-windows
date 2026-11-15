@{
    SchemaVersion = 1
    Name = 'qwen38-r6-rocm-256k-mtp-off-on-20261030'

    # Overnight two-run control for ROCm long-context investigation.
    # Order: exactly one MTP OFF run, then exactly one MTP ON run.
    # The ON condition matches the earlier b11908 256k ROCm DENSE+NOOP ON
    # operational profile (184.79 PP / 15.04 TG tok/s; single historical run).
    # Do not turn this into an ABBA or add other cases/variants.
    #
    # Prerequisites: CombinedROCm must select the verified b11908 TheRock 10.0
    # executable/runtime; UnslothPle16 and UnslothMtp point at the previously
    # measured model files; Inputs.'256k' is the 255181-token paper fixture.
    # Keep UMA 96 GiB / Performance P-MODE and ADLX monitoring available.
    # Use -PlanOnly and verify exactly 2 runs before unattended execution.
    Settings = @{
        CooldownSeconds = 60
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
            Mtp              = $false
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
            Name = 'r6-rocm-iq3-256k-mtp-off-on'
            Tool = 'cli'
            BuildKeys = @('CombinedROCm')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '256k'; Parameters = @{ Context = 262144; InputKey = '256k' } }
            )
            Variants = @(
                @{
                    Name = '01-mtp-off'
                    Parameters = @{
                        Mtp           = $false
                        DraftModelKey = ''
                        DraftModel    = ''
                    }
                }
                @{
                    Name = '02-mtp-on-dense-noop'
                    Parameters = @{
                        Mtp           = $true
                        DraftModelKey = 'UnslothMtp'
                    }
                    Environment = @{
                        LLAMA_MTP_SKIP_DENSE_INDEXER     = '1'
                        LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
                    }
                }
            )
        }
    )
}
