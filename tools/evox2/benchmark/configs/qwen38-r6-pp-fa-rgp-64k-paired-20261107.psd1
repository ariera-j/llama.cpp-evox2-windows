@{
    SchemaVersion = 1
    Name = 'qwen38-r6-pp-fa-rgp-64k-paired-20261107'

    # RGP markers ONLY. Dispatch timing is captured separately by Radeon Developer Panel.
    # Run exactly ONE variant per invocation with -OnlyVariant.
    # These labels cover physical N=1024 FA dispatches, NOT just the 64-Query F16 crop.
    # RDP settings: qwen38-r6-pp-fa-rgp-rdp-settings-20261107.json
    # Runbook: docs/evox2/R6-PP-FA-RGP-64K-PAIRED-CAPTURE-2026-11-07.md
    Settings = @{
        CooldownSeconds = 10
        ContinueOnError = $false
    }
    Defaults = @{
        BenchParameters = @{
            PromptTokens     = @(61777)
            GenerationTokens = @(0)
            Depths           = @(0)
            Context          = 65536
            Repetitions      = 1
            NoWarmup         = $true
            PromptSlice      = 'head'
            KvType           = 'f16'
            Batch            = 2048
            UBatch           = 1024
            Threads          = 4
            GpuLayers        = 999
            CpuMoe           = 0
            FlashAttn        = 'auto'
            ResourceMonitor  = $true
        }
        Environment = @{
            GGML_VK_QSA_UNION                   = '0'
            GGML_VK_QSA_UNION_STATS             = $null
            GGML_VK_QSA_UNION_STATS_FILE        = $null
            QWEN4EXP_QSA_GATHER                 = '0'
            GGML_VK_FA_RGP_MARKERS              = '1'

            # Do not mix RGP GPU timings with readback/CPU-ordinal instrumentation.
            GGML_VK_DEBUG_MARKERS               = $null
            GGML_VK_FA_DISPATCH_TRACE           = $null
            GGML_VK_FA_DISPATCH_DIAG            = $null
            GGML_VK_FA_MASK_DIAG                = $null
            GGML_VK_FA_MASK_DIAG_KV             = $null
            GGML_VK_FA_MASK_DIAG_QUERY          = $null
            GGML_VK_FA_MASK_DIAG_FILE           = $null
            GGML_VK_FA_MASK_DIAG_RAW            = $null
            GGML_VK_FA_MASK_DIAG_RAW_Q_TILE     = $null
            GGML_VK_FA_MASK_DIAG_RAW_K_TILE     = $null
            GGML_VK_INDEXER_DIAG                = $null
            GGML_VK_INDEXER_DIAG_KV             = $null
            GGML_VK_INDEXER_DIAG_LAYER          = $null
            GGML_VK_INDEXER_DIAG_Q_START        = $null
            GGML_VK_INDEXER_DIAG_Q_COUNT        = $null
            GGML_VK_INDEXER_DIAG_FILE           = $null
            GGML_VK_PERF_LOGGER                 = $null
            GGML_VK_PERF_LOGGER_CONCURRENT      = $null
            GGML_VK_FA_SPARSE_DISABLE           = $null
            GGML_VK_MTP_PP_RGP_MARKERS          = $null
            GGML_VK_MTP_PP_RGP_DISPATCH_TRACE   = $null
            LLAMA_MTP_DIAG                      = $null
        }
    }
    Jobs = @(
        @{
            Name = 'vulkan-rgp-code-64k'
            Tool = 'bench'
            BuildKeys = @('R6PpFaRgpVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{
                    Name = 'code-head-61777'
                    Parameters = @{
                        InputFile = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\qsa-code-test\llamacpp-inference-code.txt'
                    }
                }
            )
            Variants = @(
                @{ Name = 'rgp-code-64k'; Environment = @{ GGML_VK_FA_RGP_MARKERS = '1' } }
            )
        }
        @{
            Name = 'vulkan-rgp-literature-64k'
            Tool = 'bench'
            BuildKeys = @('R6PpFaRgpVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{
                    Name = 'literature-head-61777'
                    Parameters = @{
                        InputFile = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\wagahaiwa_nekodearu_utf8.txt'
                    }
                }
            )
            Variants = @(
                @{ Name = 'rgp-literature-64k'; Environment = @{ GGML_VK_FA_RGP_MARKERS = '1' } }
            )
        }
    )
}
