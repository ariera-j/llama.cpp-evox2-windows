@{
    SchemaVersion = 1
    Name = 'qwen38-r6-rocm-fa-kvmax-diag-20261108'
    # Deliberate GPU->host synchronization in only one target FA op.
    # NOT a PP timing measurement; RGP and all other diagnostic anchors OFF.
    Settings = @{ CooldownSeconds = 15; ContinueOnError = $false }
    Defaults = @{
        BenchParameters = @{
            PromptTokens     = @(32768)
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
            GGML_CUDA_DISABLE_GRAPHS           = '1'
            GGML_HIP_KVMAX_DIAG                = '1'
            GGML_HIP_KVMAX_DIAG_KV             = '32768'
            GGML_HIP_KVMAX_DIAG_LAYER          = '19'
            GGML_HIP_RGP_ANCHOR                = $null
            GGML_HIP_RGP_ANCHOR_KV             = $null
            GGML_HIP_RGP_ANCHOR_PROBE_ALL_MOE  = $null
            GGML_HIP_MMQ_TRACE                = $null
            GGML_HIP_FA_TRACE                 = '1'
            GGML_HIP_FA_TRACE_KV              = '32768'
            GGML_HIP_FA_TRACE_LAYER           = '19'
            GGML_EVOX2_MOE_TOPK_TRACE         = $null
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
            Name = 'rocm-fa-kvmax-code'
            Tool = 'bench'
            BuildKeys = @('R6RocmFaKvmaxDiag')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{
                    Name = 'code-head-32768'
                    Parameters = @{
                        InputFile = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\qsa-code-test\llamacpp-inference-code.txt'
                    }
                }
            )
            Variants = @(
                @{ Name = 'kvmax-code-32768-layer19' }
            )
        }
        @{
            Name = 'rocm-fa-kvmax-literature'
            Tool = 'bench'
            BuildKeys = @('R6RocmFaKvmaxDiag')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{
                    Name = 'literature-head-32768'
                    Parameters = @{
                        InputFile = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\wagahaiwa_nekodearu_utf8.txt'
                    }
                }
            )
            Variants = @(
                @{ Name = 'kvmax-literature-32768-layer19' }
            )
        }
    )
}
