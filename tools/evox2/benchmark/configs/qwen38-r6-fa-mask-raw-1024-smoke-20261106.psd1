@{
    SchemaVersion = 1
    Name = 'qwen38-r6-fa-mask-raw-1024-smoke-20261106'
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
            GGML_VK_QSA_UNION                 = '0'
            GGML_VK_QSA_UNION_STATS           = $null
            GGML_VK_DEBUG_MARKERS             = $null
            GGML_VK_FA_RGP_MARKERS            = $null
            GGML_VK_FA_DISPATCH_TRACE         = $null
            GGML_VK_FA_MASK_DIAG              = $null
            GGML_VK_FA_MASK_DIAG_KV           = $null
            GGML_VK_FA_MASK_DIAG_QUERY        = $null
            GGML_VK_FA_MASK_DIAG_FILE         = $null
            GGML_VK_FA_MASK_DIAG_RAW          = $null
            GGML_VK_FA_MASK_DIAG_RAW_Q_TILE   = $null
            GGML_VK_FA_MASK_DIAG_RAW_K_TILE   = $null
            GGML_VK_FA_DISPATCH_DIAG          = $null
            GGML_VK_PERF_LOGGER               = $null
            GGML_VK_PERF_LOGGER_CONCURRENT    = $null
            QWEN4EXP_QSA_GATHER               = '0'
            LLAMA_MTP_DIAG                    = $null
        }
    }
    Jobs = @(
        @{
            Name = 'vulkan-fa-raw-mask-smoke-1024'
            Tool = 'bench'
            BuildKeys = @('R6PpFaRgpVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{
                    Name = 'literature-head-1024'
                    Parameters = @{
                        InputFile = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\wagahaiwa_nekodearu_utf8.txt'
                    }
                }
            )
            Variants = @(
                @{
                    Name = 'raw-mask-smoke-1024'
                    Environment = @{
                        GGML_VK_FA_MASK_DIAG            = '1'
                        GGML_VK_FA_MASK_DIAG_KV         = '1024'
                        GGML_VK_FA_MASK_DIAG_QUERY      = 'Qcur-19'
                        GGML_VK_FA_MASK_DIAG_RAW       = '1'
                        # 4x4 tile crop: query 512..575, key 512..767;
                        # known causal boundary includes MIXED and ALL_NEG_INF.
                        GGML_VK_FA_MASK_DIAG_RAW_Q_TILE = '32'
                        GGML_VK_FA_MASK_DIAG_RAW_K_TILE = '8'
                        GGML_VK_FA_MASK_DIAG_FILE      = 'C:\llama-build\evox2-ppdiag-mask\raw-smoke-1024-q32-k8'
                    }
                }
            )
        }
    )
}
