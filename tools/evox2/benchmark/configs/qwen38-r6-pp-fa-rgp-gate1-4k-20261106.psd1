@{
    SchemaVersion = 1
    Name = 'qwen38-r6-pp-fa-rgp-gate1-4k-20261106'

    # Gate1: 4k RGP label visibility and CPU/RDP ordinal calibration ONLY.
    # The same validated b12100 diagnostic Vulkan binary is reused; NO new code build.
    # The two variants must be run SEPARATELY; never use hosttrace for GPU timings.
    Settings = @{
        CooldownSeconds = 10
        ContinueOnError = $false
    }

    Defaults = @{
        BenchParameters = @{
            PromptTokens     = @(4096)
            GenerationTokens = @(0)
            Depths           = @(0)
            Context          = 8192
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
            GGML_VK_QSA_UNION_STATS_FILE      = $null
            GGML_VK_DEBUG_MARKERS             = $null
            GGML_VK_FA_RGP_MARKERS            = $null
            GGML_VK_FA_DISPATCH_TRACE         = $null
            GGML_VK_FA_MASK_DIAG              = $null
            GGML_VK_FA_DISPATCH_DIAG          = $null
            GGML_VK_PERF_LOGGER               = $null
            GGML_VK_PERF_LOGGER_CONCURRENT    = $null
            GGML_VK_FA_SPARSE_DISABLE         = $null
            GGML_VK_MTP_PP_RGP_MARKERS        = $null
            GGML_VK_MTP_PP_RGP_DISPATCH_TRACE = $null
            QWEN4EXP_QSA_GATHER               = '0'
            LLAMA_MTP_DIAG                    = $null
        }
    }

    Jobs = @(
        @{
            Name = 'vulkan-fa-rgp-4k'
            Tool = 'bench'
            BuildKeys = @('R6PpFaRgpVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{
                    Name = 'literature-head-4096'
                    Parameters = @{
                        InputFile = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\wagahaiwa_nekodearu_utf8.txt'
                    }
                }
            )
            Variants = @(
                # First run without RDP: determine whether all 4 physical
                # microbatches/FA operations are observed. Tracing adds CPU IO.
                @{
                    Name = 'hosttrace-4k'
                    Environment = @{
                        GGML_VK_FA_RGP_MARKERS = '1'
                        GGML_VK_FA_DISPATCH_TRACE = '1'
                    }
                }
                # Second run with RDP pre-armed: RGP labels only; host tracing
                # OFF so I/O does not perturb the GPU capture timing.
                @{
                    Name = 'rgp-markers-4k'
                    Environment = @{
                        GGML_VK_FA_RGP_MARKERS = '1'
                        GGML_VK_FA_DISPATCH_TRACE = $null
                    }
                }
            )
        }
    )
}
