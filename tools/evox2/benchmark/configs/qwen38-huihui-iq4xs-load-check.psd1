@{
    SchemaVersion = 1
    Name = 'qwen38-huihui-iq4xs-load-check'

    # Large huihui-ai (Unsloth UD-IQ4_XS-based) GGUF.
    # This is a LOAD / ALLOCATION smoke test, NOT a long-prompt PP benchmark.
    #
    # Run one context size at a time with -OnlyCase:
    #   4k -> 16k -> 32k -> 64k -> 96k -> 128k
    # Inspect resources.csv and stderr.log before advancing.
    # Each selected case runs CleanVulkan first, then CleanROCm, sequentially.
    # Historical original-layout ROCm tests stopped at 16k: PLE remained on
    # the CPU (~26.82 GiB). Do not advance to 32k+ without reviewing RAM.

    Settings = @{
        CooldownSeconds = 15
        ContinueOnError = $false
    }

    Defaults = @{
        CliParameters = @{
            AllocationOnly          = $true
            KvType                  = 'f16'
            Context                 = 4096
            UBatch                  = 512
            Batch                   = 2048
            Threads                 = 4
            GpuLayers               = 999
            CpuMoe                  = 0
            FlashAttn               = 'auto'
            Verbosity               = 4
            PromptCacheMiB          = 0
            Temperature             = 0.2
            TopP                    = 0.8
            Reasoning               = 'off'
            Fit                     = 'on'
            Mtp                     = $false
            ResourceMonitor         = $true
            ResourceIntervalSeconds = 1
            ProgressIntervalSeconds = 15

            # Match the usual r5 execution environment without enabling MTP.
            ExtraArgs = @(
                '-tb'
                '4'
                '--ctx-checkpoints'
                '0t'
            )
        }

        # Make the run independent of inherited downstream diagnostic flags.
        Environment = @{
            GGML_VK_QSA_UNION                   = $null
            GGML_VK_QSA_UNION_STATS             = $null
            GGML_VK_QSA_UNION_STATS_FILE        = $null
            GGML_VK_QSA_UNION_STATS_KV_BIN      = $null
            GGML_VK_QSA_UNION_MIN_KV            = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER       = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION   = $null
            LLAMA_MTP_DIAG                     = $null
            LLAMA_MTP_QSA_MIN_KV               = $null
            LLAMA_QSA_NO_POOLED_CACHE          = $null
            LLAMA_QSA_POOLED_MAX_TOKENS        = $null
            QWEN4EXP_QSA_GATHER                = $null
            GGML_VK_GET_ROWS_128X4             = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE     = $null
            LLAMA_GRAPH_REUSE_DISABLE         = $null
            GGML_VK_FUSE_UNARY_MUL              = $null
            GGML_VK_SHMEM_PAD                   = $null
            GGML_VK_DENSE_WAVE32               = $null
            GGML_VK_MOE_LEGACY_TILE_SELECTION  = $null
            GGML_VK_MOE_TILE_LOG               = $null
            GGML_VK_PERF_GET_ROWS_DETAILS      = $null
            EVOX2_AB_RUN                       = $null
            EVOX2_ABBA_RUN                     = $null
        }
    }

    Jobs = @(
        @{
            Name = 'iq4xs-load'
            Tool = 'cli'
            BuildKeys = @('CleanVulkan', 'CleanROCm')
            ModelKeys = @('HuihuiIQ4XS')

            Cases = @(
                @{ Name = '4k';   Parameters = @{ Context = 4096   } }
                @{ Name = '16k';  Parameters = @{ Context = 16384  } }
                @{ Name = '32k';  Parameters = @{ Context = 32768  } }
                @{ Name = '64k';  Parameters = @{ Context = 65536  } }
                @{ Name = '96k';  Parameters = @{ Context = 98304  } }
                @{ Name = '128k'; Parameters = @{ Context = 131072 } }
            )

            Variants = @(
                @{ Name = 'allocation-nomtp'; Parameters = @{} }
            )
        }
    )
}
