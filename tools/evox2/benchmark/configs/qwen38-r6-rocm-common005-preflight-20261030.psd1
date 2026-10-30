@{
    SchemaVersion = 1
    Name = 'qwen38-r6-rocm-common005-preflight-20261030'

    # Extra pre-implementation baseline coverage for ROCm MTP-OFF QSA gather.
    # Exactly 3 separate CLI runs in order:
    #   1. 128k MTP OFF, new resource monitor ON (2s / background 15s)
    #   2. 256k MTP OFF, resource monitor OFF (ADLX/P-MODE retained)
    #   3. 256k MTP OFF, new resource monitor ON (same as the 2026-10-30 run)
    # All 3 share the frozen b11908 TheRock 10.0 CLI, IQ3 PLE16 model,
    # 512 generated tokens, temp 0, seed 1234, no context checkpoints.
    # OFF here disables only the resource monitor subprocess; wrapper
    # start/end background snapshots and ADLX GPU sampling still run.
    # These single runs screen for overhead/variance; they do NOT prove causality.
    # No r3/COMMON-005 patch is loaded. Never run the unsafe broad HIP FA suite.
    # Preconditions: CombinedROCm selects verified b11908 TheRock 10.0,
    # UnslothPle16 points at the same model; Inputs.128k / Inputs.256k
    # resolve to 126253 / 255181 actual prompt tokens; 96GiB UMA, P-MODE
    # Performance. PlanOnly must show exactly three cases in order.
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
            ResourceIntervalSeconds   = 2
            BackgroundIntervalSeconds = 15
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
            Name = 'r6-rocm-common005-mtp-off-preflight'
            Tool = 'cli'
            BuildKeys = @('CombinedROCm')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{
                    Name = '01-128k-monitored'
                    Parameters = @{ Context = 131072; InputKey = '128k' }
                }
                @{
                    Name = '02-256k-resource-off'
                    Parameters = @{ Context = 262144; InputKey = '256k'; ResourceMonitor = $false }
                }
                @{
                    Name = '03-256k-monitored-repeat'
                    Parameters = @{ Context = 262144; InputKey = '256k'; ResourceMonitor = $true }
                }
            )
            Variants = @(
                @{ Name = 'mtp-off-control' }
            )
        }
    )
}
