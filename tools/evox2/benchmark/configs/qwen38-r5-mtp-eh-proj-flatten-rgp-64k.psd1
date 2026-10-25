@{
    SchemaVersion = 1
    Name = 'qwen38-r5-mtp-eh-proj-flatten-rgp-64k'

    # GPU profiling only. Never use PP/TG from this plan as benchmark numbers.
    # Run after the non-profiled 64k ABBA establishes whether flattening helps.
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
            Mtp              = $true
            DraftModelKey    = 'UnslothMtp'
            DraftMax         = 2
            DraftPMin        = 0.0
            ResourceMonitor  = $true
            ExtraArgs        = @('-tb', '4', '--ctx-checkpoints', '0t',
                                 '--seed', '1234', '--ignore-eos')
        }
        Environment = @{
            LLAMA_MTP_DRAFT_PREFILL_KV_CROP    = '1'
            LLAMA_MTP_EH_PROJ_FLATTEN          = $null

            GGML_VK_QSA_UNION                  = '1'
            GGML_VK_QSA_UNION_MIN_KV           = '32768'

            # RGP role/range calibration only.
            GGML_VK_MTP_PP_RGP_MARKERS         = '1'
            GGML_VK_MTP_PP_RGP_DISPATCH_TRACE  = '1'
            LLAMA_MTP_PP_TRACE                 = 'detail'

            LLAMA_MTP_KV_CROP_DIAG             = $null
            LLAMA_MTP_DIAG                     = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER       = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION   = $null
            GGML_VK_QSA_UNION_STATS            = $null
            GGML_VK_PERF_LOGGER                = $null
            GGML_VK_PERF_LOGGER_CONCURRENT     = $null
            GGML_VK_DEBUG_MARKERS              = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE     = $null
            LLAMA_GRAPH_REUSE_DISABLE          = $null
            LLAMA_MTP_QSA                      = $null
            LLAMA_MTP_QSA_MIN_KV               = $null
        }
    }

    Jobs = @(
        @{
            Name      = 'eh-proj-rgp-64k'
            Tool      = 'cli'
            BuildKeys = @('R5MtpEhProjFlattenVulkan')
            ModelKeys = @('UnslothPle16')
            Cases     = @(@{
                Name = '64k'
                Parameters = @{
                    Context  = 65536
                    InputKey = '64k'
                }
            })
            Variants = @(
                # A is optional if the retained b11618 RGP is sufficient for orientation.
                # Use it when an exact same-binary RGP comparison is desired.
                @{ Name = 'A-flat-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_EH_PROJ_FLATTEN = '0' } }
                @{ Name = 'B-flat-on';  Parameters = @{}; Environment = @{ LLAMA_MTP_EH_PROJ_FLATTEN = '1' } }
            )
        }
    )
}
