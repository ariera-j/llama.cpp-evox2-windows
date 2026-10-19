@{
    SchemaVersion = 1
    Name = 'qwen38-r5-mtp-eh-proj-flatten'

    # PP-only geometry experiment. Stage-B Draft KV-only catch-up remains ON in
    # every arm. A/B differs only by LLAMA_MTP_EH_PROJ_FLATTEN.
    # Define R5MtpEhProjFlattenVulkan in ignored local.psd1.
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
            # Stage-B is a fixed prerequisite in both arms. The flatten source
            # guard additionally requires this zero-output Draft catch-up path.
            LLAMA_MTP_DRAFT_PREFILL_KV_CROP   = '1'
            LLAMA_MTP_EH_PROJ_FLATTEN         = $null

            GGML_VK_QSA_UNION                 = '1'
            GGML_VK_QSA_UNION_MIN_KV          = '32768'

            # Timing cohort: keep all diagnostics/profilers off.
            LLAMA_MTP_KV_CROP_DIAG            = $null
            LLAMA_MTP_PP_TRACE                = $null
            LLAMA_MTP_DIAG                    = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER      = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION  = $null
            GGML_VK_QSA_UNION_STATS           = $null
            GGML_VK_PERF_LOGGER               = $null
            GGML_VK_PERF_LOGGER_CONCURRENT    = $null
            GGML_VK_DEBUG_MARKERS             = $null
            GGML_VK_MTP_PP_RGP_MARKERS        = $null
            GGML_VK_MTP_PP_RGP_DISPATCH_TRACE = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE    = $null
            LLAMA_GRAPH_REUSE_DISABLE         = $null
            LLAMA_MTP_QSA                     = $null
            LLAMA_MTP_QSA_MIN_KV              = $null
        }
    }

    Jobs = @(
        @{
            Name      = 'eh-proj-short'
            Tool      = 'cli'
            BuildKeys = @('R5MtpEhProjFlattenVulkan')
            ModelKeys = @('UnslothPle16')
            Cases     = @(@{
                Name = 'smoke'
                Parameters = @{
                    Context          = 32768
                    InputFile        = 'tools\evox2\benchmark\inputs\mtp-short.txt'
                    GenerationTokens = 32
                }
            })
            Variants = @(
                @{ Name = 'A-flat-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_EH_PROJ_FLATTEN = '0' } }
                @{ Name = 'B-flat-on';  Parameters = @{}; Environment = @{ LLAMA_MTP_EH_PROJ_FLATTEN = '1' } }
            )
        }
        @{
            Name      = 'eh-proj-64k-abba'
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
                @{ Name = 'A1-flat-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_EH_PROJ_FLATTEN = '0'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1-flat-on';  Parameters = @{}; Environment = @{ LLAMA_MTP_EH_PROJ_FLATTEN = '1'; EVOX2_ABBA_RUN = 'B1' } }
                @{ Name = 'B2-flat-on';  Parameters = @{}; Environment = @{ LLAMA_MTP_EH_PROJ_FLATTEN = '1'; EVOX2_ABBA_RUN = 'B2' } }
                @{ Name = 'A2-flat-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_EH_PROJ_FLATTEN = '0'; EVOX2_ABBA_RUN = 'A2' } }
            )
        }
        @{
            Name      = 'eh-proj-128k-abba'
            Tool      = 'cli'
            BuildKeys = @('R5MtpEhProjFlattenVulkan')
            ModelKeys = @('UnslothPle16')
            Cases     = @(@{
                Name = '128k'
                Parameters = @{
                    Context  = 131072
                    InputKey = '128k'
                }
            })
            Variants = @(
                @{ Name = 'A1-flat-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_EH_PROJ_FLATTEN = '0'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1-flat-on';  Parameters = @{}; Environment = @{ LLAMA_MTP_EH_PROJ_FLATTEN = '1'; EVOX2_ABBA_RUN = 'B1' } }
                @{ Name = 'B2-flat-on';  Parameters = @{}; Environment = @{ LLAMA_MTP_EH_PROJ_FLATTEN = '1'; EVOX2_ABBA_RUN = 'B2' } }
                @{ Name = 'A2-flat-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_EH_PROJ_FLATTEN = '0'; EVOX2_ABBA_RUN = 'A2' } }
            )
        }
        @{
            Name      = 'eh-proj-128k-mtp-off-control'
            Tool      = 'cli'
            BuildKeys = @('R5MtpEhProjFlattenVulkan')
            ModelKeys = @('UnslothPle16')
            # Optional only after a positive 128k flatten result. This updates
            # the residual MTP-ON vs MTP-OFF estimate with the same new binary.
            Parameters = @{
                Mtp           = $false
                DraftModelKey = ''
            }
            Environment = @{
                LLAMA_MTP_DRAFT_PREFILL_KV_CROP = $null
                LLAMA_MTP_EH_PROJ_FLATTEN       = $null
            }
            Cases = @(@{
                Name = '128k'
                Parameters = @{
                    Context  = 131072
                    InputKey = '128k'
                }
            })
            Variants = @(
                @{ Name = 'MTP-off'; Parameters = @{}; Environment = @{} }
            )
        }
    )
}
