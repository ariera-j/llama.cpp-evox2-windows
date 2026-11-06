@{
    SchemaVersion = 1
    Name = 'qwen38-r6-indexer-score-64k-20261106'
    # Original F32 lightning-indexer scores and I32 top-k pool indices, one diagnostic run per corpus.
    # The two variants MUST be selected separately.
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
            GGML_VK_FA_SPARSE_DISABLE         = $null
            QWEN4EXP_QSA_GATHER               = '0'
            LLAMA_MTP_DIAG                    = $null
        }
    }
    Jobs = @(
        @{
            Name = 'code-indexer-score-topk'
            Tool = 'bench'
            BuildKeys = @('R6PpFaRgpVulkan')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{
                    Name = 'source-head-61777'
                    Parameters = @{
                        InputFile = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\qsa-code-test\llamacpp-inference-code.txt'
                    }
                }
            )
            Variants = @(
                @{
                    Name = 'idx-code'
                    Environment = @{
                        GGML_VK_INDEXER_DIAG              = '1'
                        GGML_VK_INDEXER_DIAG_KV           = '49152'
                        GGML_VK_INDEXER_DIAG_LAYER        = '19'
                        GGML_VK_INDEXER_DIAG_Q_START      = '512'
                        GGML_VK_INDEXER_DIAG_Q_COUNT      = '64'
                        GGML_VK_INDEXER_DIAG_FILE         = 'C:\llama-build\evox2-ppdiag-indexer\idx-code-kv49152-il19'
                    }
                }
            )
        }
        @{
            Name = 'literature-indexer-score-topk'
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
                @{
                    Name = 'idx-literature'
                    Environment = @{
                        GGML_VK_INDEXER_DIAG              = '1'
                        GGML_VK_INDEXER_DIAG_KV           = '49152'
                        GGML_VK_INDEXER_DIAG_LAYER        = '19'
                        GGML_VK_INDEXER_DIAG_Q_START      = '512'
                        GGML_VK_INDEXER_DIAG_Q_COUNT      = '64'
                        GGML_VK_INDEXER_DIAG_FILE         = 'C:\llama-build\evox2-ppdiag-indexer\idx-literature-kv49152-il19'
                    }
                }
            )
        }
    )
}
