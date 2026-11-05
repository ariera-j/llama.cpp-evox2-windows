@{
    SchemaVersion = 1
    Name = 'qwen38-r6-pp-fa-rgp-gate1-20261105'

    # GATE 1 ONLY. Short prompt tests of marker-only Vulkan instrumentation.
    # The OFF control and ON case use the SAME newly compiled diagnostic binary.
    # Do not use RGP/marker-on times as a production PP benchmark.
    # The 64k test is intentionally excluded until the native short + RGP gate passes.
    Settings = @{
        CooldownSeconds = 10
        ContinueOnError = $false
    }

    Defaults = @{
        BenchParameters = @{
            PromptTokens     = @(1024)
            GenerationTokens = @(0)
            Depths           = @(0)
            Context          = 2048
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
            GGML_VK_DEBUG_MARKERS               = $null
            GGML_VK_FA_RGP_MARKERS              = $null
            GGML_VK_FA_MASK_DIAG                = $null
            GGML_VK_FA_DISPATCH_DIAG            = $null
            GGML_VK_PERF_LOGGER                 = $null
            GGML_VK_PERF_LOGGER_CONCURRENT      = $null
            GGML_VK_FA_SPARSE_DISABLE           = $null
            GGML_VK_MTP_PP_RGP_MARKERS          = $null
            GGML_VK_MTP_PP_RGP_DISPATCH_TRACE   = $null
            QWEN4EXP_QSA_GATHER                 = '0'
            LLAMA_MTP_DIAG                      = $null
        }
    }

    Jobs = @(
        @{
            Name = 'vulkan-fa-rgp-short'
            Tool = 'bench'
            BuildKeys = @('R6PpFaRgpVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{
                    Name = 'literature-1024'
                    Parameters = @{
                        InputFile = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\wagahaiwa_nekodearu_utf8.txt'
                    }
                }
            )
            Variants = @(
                @{ Name = 'markers-off-control'; Environment = @{ GGML_VK_FA_RGP_MARKERS = $null } }
                @{ Name = 'markers-on';          Environment = @{ GGML_VK_FA_RGP_MARKERS = '1' } }
            )
        }
    )
}
