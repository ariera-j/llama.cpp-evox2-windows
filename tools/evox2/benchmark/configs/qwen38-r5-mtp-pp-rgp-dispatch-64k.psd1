@{
    SchemaVersion = 1
    Name = 'qwen38-r5-mtp-pp-rgp-dispatch-64k'

    # DIAGNOSTIC ONLY. Count vkCmdDispatch ordinals per Target/Draft graph.
    # Point R5MtpRgpDispatchVulkan at a NEWLY BUILT binary from
    # investigation/r5-mtp-pp-trace-20261013 (not the prior b11569).
    # GPU marker overhead alters timings; never use this plan for PP A/B.
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
            GGML_VK_PERF_LOGGER_CONCURRENT   = $null
            GGML_VK_DEBUG_MARKERS            = $null
            GGML_VK_FA_RGP_MARKERS           = $null
            GGML_VK_FA_DISPATCH_DIAG         = $null
            GGML_VK_FA_MASK_DIAG             = $null
            GGML_VK_MTP_PP_RGP_MARKERS       = $null
            GGML_VK_MTP_PP_RGP_DISPATCH_TRACE = $null
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
            BuildKeys = @('R5MtpRgpDispatchVulkan')
            ModelKeys = @('UnslothPle16')
            Environment = @{
                GGML_VK_QSA_UNION        = '1'
                GGML_VK_QSA_UNION_MIN_KV = '32768'
                LLAMA_MTP_PP_TRACE      = 'detail'
                GGML_VK_MTP_PP_RGP_MARKERS = '1'
                GGML_VK_MTP_PP_RGP_DISPATCH_TRACE = '1'
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
            BuildKeys = @('R5MtpRgpDispatchVulkan')
            ModelKeys = @('UnslothPle16')
            Environment = @{
                GGML_VK_QSA_UNION        = '1'
                GGML_VK_QSA_UNION_MIN_KV = '32768'
                LLAMA_MTP_PP_TRACE      = 'detail'
                GGML_VK_MTP_PP_RGP_MARKERS = '1'
                GGML_VK_MTP_PP_RGP_DISPATCH_TRACE = '1'
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
