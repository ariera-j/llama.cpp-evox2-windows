@{
    SchemaVersion = 1
    Name = 'qwen38-r6-rocm-pp-fa-rgp-64k-realprompt-20261107'

    # ROCm/HIP QSA FA PP: one native job at a time.
    # NOTE: pre-TOOL-001 b11908 CombinedROCm and b12013 R6RocmCommon005
    # llama-bench do NOT have -f/--prompt-file or --prompt-slice;
    # do not replace this BuildKey with either older binary.
    #
    # Baseline real-prompt b12038 is proven functional (2026-11-03):
    # build-rocm-bench-real-r6, source d321e7ff3, expected ROCm.
    # local.psd1: Builds.R6RocmRealPromptRgp (map to its verified BinDir).
    #
    # The GPU profiler's HIP RGP event list has NO Vulkan debug user markers.
    # Runbook: docs/evox2/R6-ROCM-PP-FA-RGP-64K-CAPTURE-RUNBOOK-2026-11-07.md
    Settings = @{
        CooldownSeconds = 15
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
            # For true Vulkan-vs-ROCm *input* comparison, leave model-graph
            # gather OFF, including in post-COMMON-005 builds.
            QWEN4EXP_QSA_GATHER              = '0'
            LLAMA_MTP_SKIP_DENSE_INDEXER    = '0'
            LLAMA_QSA_SKIP_NOOP_INVALIDATION= '0'
            LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'
            LLAMA_MTP_EH_PROJ_FLATTEN       = '0'

            # No Vulkan-only user markers, mask readback or GPU copy diagnostic.
            GGML_VK_QSA_UNION                = $null
            GGML_VK_QSA_UNION_STATS          = $null
            GGML_VK_QSA_UNION_STATS_FILE     = $null
            GGML_VK_FA_RGP_MARKERS           = $null
            GGML_VK_DEBUG_MARKERS            = $null
            GGML_VK_FA_DISPATCH_TRACE        = $null
            GGML_VK_FA_DISPATCH_DIAG         = $null
            GGML_VK_FA_MASK_DIAG             = $null
            GGML_VK_FA_MASK_DIAG_RAW         = $null
            GGML_VK_INDEXER_DIAG             = $null
            GGML_VK_PERF_LOGGER              = $null
            GGML_VK_FA_SPARSE_DISABLE        = $null
            LLAMA_GRAPH_REUSE_DISABLE       = $null
            LLAMA_MTP_DIAG                   = $null
        }
    }
    Jobs = @(
        @{
            Name = 'rocm-realprompt-smoke-code-1024'
            Tool = 'bench'
            BuildKeys = @('R6RocmRealPromptRgp')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{
                    Name = 'code-head-1024'
                    Parameters = @{
                        Context = 2048
                        PromptTokens = @(1024)
                        InputFile = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\qsa-code-test\llamacpp-inference-code.txt'
                    }
                }
            )
            Variants = @(
                @{ Name = 'rocm-code-smoke-1024' }
            )
        }
        @{
            Name = 'rocm-rgp-code-64k'
            Tool = 'bench'
            BuildKeys = @('R6RocmRealPromptRgp')
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
                @{ Name = 'rocm-code-64k' }
            )
        }
        @{
            Name = 'rocm-rgp-literature-64k'
            Tool = 'bench'
            BuildKeys = @('R6RocmRealPromptRgp')
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
                @{ Name = 'rocm-literature-64k' }
            )
        }
    )
}
