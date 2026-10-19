@{
    SchemaVersion = 1
    Name = 'qwen38-r5-mtp-pp-trace-64k'

    # DIAGNOSTIC ONLY. Point R5Common001Vulkan at the *newly built PP trace*
    # experiment executable in ignored local.psd1. Do not silently run b11560.
    # This is not an ABBA speed baseline: trace-enabled wall times are perturbed.
    Settings = @{
        CooldownSeconds = 10
        ContinueOnError = $false
    }

    Defaults = @{
        CliParameters = @{
            KvType           = 'f16'
            UBatch           = 1024
            Batch            = 2048
            Threads          = 4
            GpuLayers        = 999
            CpuMoe           = 0
            FlashAttn        = 'auto'
            Verbosity        = 4
            GenerationTokens = 512
            PromptCacheMiB   = 0
            Temperature      = 0.0
            TopP             = 0.8
            Reasoning        = 'off'
            Fit              = 'off'
            Mtp              = $false
            ResourceMonitor  = $true
            ExtraArgs = @('-tb', '4', '--ctx-checkpoints', '0t',
                          '--seed', '1234', '--ignore-eos')
        }
        Environment = @{
            LLAMA_MTP_PP_TRACE               = $null
            LLAMA_MTP_DIAG                   = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER     = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION = $null
            GGML_VK_QSA_UNION                = $null
            GGML_VK_QSA_UNION_MIN_KV         = $null
            GGML_VK_QSA_UNION_STATS          = $null
            GGML_VK_PERF_LOGGER              = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE   = $null
            LLAMA_GRAPH_REUSE_DISABLE       = $null
            LLAMA_MTP_QSA                   = $null
            LLAMA_MTP_QSA_MIN_KV            = $null
        }
    }

    Jobs = @(
        @{
            Name = 'vulkan-short'
            Tool = 'cli'
            BuildKeys = @('R5Common001Vulkan')
            ModelKeys = @('UnslothPle16')
            Environment = @{
                GGML_VK_QSA_UNION        = '1'
                GGML_VK_QSA_UNION_MIN_KV = '32768'
                LLAMA_MTP_PP_TRACE      = 'detail'
            }
            Cases = @(@{
                Name = 'smoke'
                Parameters = @{
                    Context = 32768
                    InputFile = 'tools\evox2\benchmark\inputs\mtp-short.txt'
                    GenerationTokens = 32
                }
            })
            Variants = @(
                @{ Name = 'off-detail'; Parameters = @{} }
                @{ Name = 'on-detail'; Parameters = @{
                    Mtp = $true; DraftModelKey = 'UnslothMtp'
                    DraftMax = 2; DraftPMin = 0.0
                } }
            )
        }
        @{
            Name = 'vulkan-64k'
            Tool = 'cli'
            BuildKeys = @('R5Common001Vulkan')
            ModelKeys = @('UnslothPle16')
            Environment = @{
                GGML_VK_QSA_UNION        = '1'
                GGML_VK_QSA_UNION_MIN_KV = '32768'
                LLAMA_MTP_PP_TRACE      = 'detail'
            }
            Cases = @(@{
                Name = '64k'
                Parameters = @{ Context = 65536; InputKey = '64k' }
            })
            Variants = @(
                @{ Name = 'off-detail'; Parameters = @{} }
                @{ Name = 'on-detail'; Parameters = @{
                    Mtp = $true; DraftModelKey = 'UnslothMtp'
                    DraftMax = 2; DraftPMin = 0.0
                } }
            )
        }
    )
}
