@{
    SchemaVersion = 1
    Name = 'qwen38-r6-rocm-moe-topk-multi-ubatch-20261107'
    # Additional samples: u15 (KV16384), u31 (KV32768); reuse existing u47 (KV49152).
    # Callback synchronizes GPU; PP timings are NOT comparable.
    # Keep same b12156 build. No new smoke/build or RGP required.
    # Run one variant at a time with -OnlyVariant, or all 4 sequentially.
    Settings = @{ CooldownSeconds = 10; ContinueOnError = $false }
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
            GGML_EVOX2_MOE_TOPK_TRACE         = '1'
            GGML_EVOX2_MOE_TOPK_UBATCH        = $null
            GGML_EVOX2_MOE_TOPK_LAYERS        = '19,23'
            GGML_EVOX2_MOE_TOPK_RAW           = '1'
            GGML_HIP_FA_TRACE                 = $null
            GGML_HIP_FA_TRACE_KV              = $null
            GGML_HIP_FA_TRACE_LAYER           = $null
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
            Name = 'rocm-moe-topk-code-samples'
            Tool = 'bench'
            BuildKeys = @('R6RocmMoeTopk')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = 'code-head-61777'
                   Parameters = @{
                       InputFile = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\qsa-code-test\llamacpp-inference-code.txt'
                   }
                }
            )
            Variants = @(
                @{ Name = 'moe-topk-code-u15'
                   Environment = @{ GGML_EVOX2_MOE_TOPK_UBATCH = '15' }
                }
                @{ Name = 'moe-topk-code-u31'
                   Environment = @{ GGML_EVOX2_MOE_TOPK_UBATCH = '31' }
                }
            )
        }
        @{
            Name = 'rocm-moe-topk-literature-samples'
            Tool = 'bench'
            BuildKeys = @('R6RocmMoeTopk')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = 'literature-head-61777'
                   Parameters = @{
                       InputFile = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\wagahaiwa_nekodearu_utf8.txt'
                   }
                }
            )
            Variants = @(
                @{ Name = 'moe-topk-literature-u15'
                   Environment = @{ GGML_EVOX2_MOE_TOPK_UBATCH = '15' }
                }
                @{ Name = 'moe-topk-literature-u31'
                   Environment = @{ GGML_EVOX2_MOE_TOPK_UBATCH = '31' }
                }
            )
        }
    )
}
