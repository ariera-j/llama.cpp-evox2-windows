@{
    SchemaVersion = 1
    Name = 'qwen38-r6-rocm-hip-fa-host-trace-64k-20261107'
    # Default-OFF diagnostic HIP source from:
    # investigation/r6-rocm-pp-fa-trace-20261107
    # Never redirect this plan to b12038 or earlier b11908/b12013:
    # only the new rebuilt R6RocmFaTrace binary contains the host trace.
    # Each variant must be run separately with -OnlyVariant.
    # HOST-ONLY metadata: not RGP GPU-time, not a full HIP dispatch ordinal.
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
            GGML_HIP_FA_TRACE                 = '1'
            GGML_HIP_FA_TRACE_KV              = '49152'
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
            Name = 'hip-fa-host-trace-smoke-code'
            Tool = 'bench'
            BuildKeys = @('R6RocmFaTrace')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = 'code-head-1024'
                   Parameters = @{
                       InputFile    = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\qsa-code-test\llamacpp-inference-code.txt'
                       PromptTokens = @(1024)
                       Context      = 2048
                   }
                }
            )
            Variants = @(
                @{ Name = 'hip-trace-smoke-code'
                   Environment = @{ GGML_HIP_FA_TRACE_KV = $null }
                }
            )
        }
        @{
            Name = 'hip-fa-host-trace-code-64k'
            Tool = 'bench'
            BuildKeys = @('R6RocmFaTrace')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = 'code-head-61777'
                   Parameters = @{
                       InputFile = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\qsa-code-test\llamacpp-inference-code.txt'
                   }
                }
            )
            Variants = @(
                @{ Name = 'hip-trace-code-64k' }
            )
        }
        @{
            Name = 'hip-fa-host-trace-literature-64k'
            Tool = 'bench'
            BuildKeys = @('R6RocmFaTrace')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = 'literature-head-61777'
                   Parameters = @{
                       InputFile = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\wagahaiwa_nekodearu_utf8.txt'
                   }
                }
            )
            Variants = @(
                @{ Name = 'hip-trace-literature-64k' }
            )
        }
    )
}
