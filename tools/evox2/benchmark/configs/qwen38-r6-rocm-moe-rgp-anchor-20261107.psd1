@{
    SchemaVersion = 1
    Name = 'qwen38-r6-rocm-moe-rgp-anchor-20261107'
    # GPU markers are only for RGP positioning, not PP performance comparison.
    Settings = @{ CooldownSeconds = 15; ContinueOnError = $false }
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
            GGML_HIP_RGP_ANCHOR               = '1'
            GGML_HIP_RGP_ANCHOR_KV            = '49152'
            GGML_HIP_RGP_ANCHOR_PROBE_ALL_MOE = $null
            GGML_HIP_MMQ_TRACE                = '1'
            GGML_HIP_FA_TRACE                 = '1'
            GGML_HIP_FA_TRACE_KV              = '49152'
            GGML_HIP_FA_TRACE_LAYER           = $null
            GGML_EVOX2_MOE_TOPK_TRACE         = $null
            GGML_EVOX2_MOE_TOPK_UBATCH        = $null
            GGML_EVOX2_MOE_TOPK_LAYERS        = $null
            GGML_EVOX2_MOE_TOPK_RAW           = $null
            QWEN4EXP_QSA_GATHER               = '0'
            LLAMA_MTP_SKIP_DENSE_INDEXER     = '0'
            LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'
            LLAMA_MTP_DRAFT_PREFILL_KV_CROP  = '0'
            LLAMA_MTP_EH_PROJ_FLATTEN        = '0'
            GGML_VK_QSA_UNION                 = $null
            GGML_VK_FA_RGP_MARKERS            = $null
            GGML_VK_DEBUG_MARKERS             = $null
            GGML_VK_FA_DISPATCH_TRACE         = $null
            GGML_VK_FA_MASK_DIAG              = $null
            GGML_VK_INDEXER_DIAG              = $null
            LLAMA_MTP_DIAG                    = $null
        }
    }
    Jobs = @(
        @{
            Name = 'rocm-moe-anchor-smoke'
            Tool = 'bench'
            BuildKeys = @('R6RocmMoeAnchorProbe')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{
                    Name = 'code-head-1024'
                    Parameters = @{
                        InputFile = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\qsa-code-test\llamacpp-inference-code.txt'
                        PromptTokens = @(1024)
                        Context = 2048
                    }
                }
            )
            Variants = @(
                @{
                    Name = 'moe-anchor-smoke'
                    Environment = @{
                        GGML_HIP_RGP_ANCHOR_KV            = '1024'
                        GGML_HIP_FA_TRACE_KV               = '1024'
                        GGML_HIP_RGP_ANCHOR_PROBE_ALL_MOE  = '1'
                    }
                }
            )
        }
        @{
            Name = 'rocm-moe-anchor-code'
            Tool = 'bench'
            BuildKeys = @('R6RocmMoeAnchorProbe')
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
                @{ Name = 'moe-anchor-code-64k' }
                @{
                    Name = 'moe-anchor-code-visibility-probe-64k'
                    Environment = @{
                        GGML_HIP_RGP_ANCHOR_PROBE_ALL_MOE = '1'
                    }
                }
            )
        }
        @{
            Name = 'rocm-moe-anchor-literature'
            Tool = 'bench'
            BuildKeys = @('R6RocmMoeAnchorProbe')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{
                    Name = 'literature-head-61777'
                    Parameters = @{
                        InputFile = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\wagahaiwa_nekodearu_utf8.txt'
                    }
                }
            )
            Variants = @( @{ Name = 'moe-anchor-literature-64k' } )
        }
    )
}
