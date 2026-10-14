@{
    SchemaVersion = 1
    Name = 'qwen38-r5-mtp-kv-crop-stage1'

    # PROTOTYPE / UNVALIDATED. All A/B variants use the *same new* binary built
    # from investigation/r5-mtp-pp-kv-crop-stage1-20261014.
    # Define R5MtpKvCropVulkan in ignored local.psd1, not the old RGP build key.
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
            ExtraArgs = @('-tb', '4', '--ctx-checkpoints', '0t',
                          '--seed', '1234', '--ignore-eos')
        }
        Environment = @{
            LLAMA_MTP_DRAFT_PREFILL_KV_CROP    = $null
            LLAMA_MTP_PP_TRACE                 = $null
            LLAMA_MTP_DIAG                     = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER       = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION   = $null
            GGML_VK_QSA_UNION                  = $null
            GGML_VK_QSA_UNION_MIN_KV           = $null
            GGML_VK_QSA_UNION_STATS            = $null
            GGML_VK_PERF_LOGGER                = $null
            GGML_VK_PERF_LOGGER_CONCURRENT     = $null
            GGML_VK_DEBUG_MARKERS              = $null
            GGML_VK_MTP_PP_RGP_MARKERS         = $null
            GGML_VK_MTP_PP_RGP_DISPATCH_TRACE  = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE     = $null
            LLAMA_GRAPH_REUSE_DISABLE         = $null
            LLAMA_MTP_QSA                      = $null
            LLAMA_MTP_QSA_MIN_KV               = $null
        }
    }

    Jobs = @(
        @{
            Name = 'stage1-short'
            Tool = 'cli'
            BuildKeys = @('R5MtpKvCropVulkan')
            ModelKeys = @('UnslothPle16')
            Environment = @{ GGML_VK_QSA_UNION = '1'; GGML_VK_QSA_UNION_MIN_KV = '32768' }
            Cases = @(@{
                Name = 'smoke'
                Parameters = @{
                    Context = 32768
                    InputFile = 'tools\evox2\benchmark\inputs\mtp-short.txt'
                    GenerationTokens = 32
                }
            })
            Variants = @(
                @{ Name = 'A-short'; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0' } }
                @{ Name = 'B-short'; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1' } }
            )
        }
        @{
            Name = 'stage1-64k'
            Tool = 'cli'
            BuildKeys = @('R5MtpKvCropVulkan')
            ModelKeys = @('UnslothPle16')
            Environment = @{ GGML_VK_QSA_UNION = '1'; GGML_VK_QSA_UNION_MIN_KV = '32768' }
            Cases = @(@{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k' } })
            Variants = @(
                @{ Name = 'A1'; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1'; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; EVOX2_ABBA_RUN = 'B1' } }
                @{ Name = 'B2'; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; EVOX2_ABBA_RUN = 'B2' } }
                @{ Name = 'A2'; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'; EVOX2_ABBA_RUN = 'A2' } }
            )
        }
    )
}
