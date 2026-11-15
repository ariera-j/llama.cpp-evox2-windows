@{
    SchemaVersion = 1
    Name = 'qwen38-huihui-iq4xs-ple16-common001'

    # huihui-ai Qwen3.8-Flash-Next UD-IQ4_XS, successfully converted to PLE16
    # and verified against original GGUF tensor payloads on 2026-10-24.
    # Use COMMON-001-capable binaries, NOT b11517 build-*-clean.
    #
    # AllocationOnly short-prompt/short-generation smoke, not a full-context
    # prefill benchmark. The recorded allocation probes used 18 prompt tokens
    # and 2 output tokens.
    # This checks model loading, context allocation and basic generation,
    # NOT full-context prefill, real-document quality, or PP throughput.
    #
    # ALWAYS gate by -OnlyCase and review memory logs before advancing:
    #     4k -> 16k -> 32k -> 64k -> 96k -> 128k.
    # Selected case runs Vulkan and then ROCm serially if both builds are
    # selected. The confirmed 4k-128k progression was Vulkan-only; the
    # single ROCm PLE16 4k check still held ~26.82 GiB PLE in CPU memory.
    # Do not expand ROCm to higher contexts as part of that validated series.

    Settings = @{
        CooldownSeconds = 15
        ContinueOnError = $false
    }

    Defaults = @{
        CliParameters = @{
            AllocationOnly          = $true
            Context                 = 4096
            KvType                  = 'f16'
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

            ExtraArgs = @(
                '-tb'
                '4'
                '--ctx-checkpoints'
                '0t'
            )
        }

        # Make placement observations comparable to the earlier clean-model
        # 4k/16k runs by clearing diagnostic and optimization overrides.
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
            Name      = 'huihui-iq4xs-ple16-load'
            Tool      = 'cli'
            BuildKeys = @('R5Common001Vulkan', 'R5Common001ROCm')
            ModelKeys = @('HuihuiIQ4XSPle16')

            Cases = @(
                @{ Name = '4k';   Parameters = @{ Context = 4096   } }
                @{ Name = '16k';  Parameters = @{ Context = 16384  } }
                @{ Name = '32k';  Parameters = @{ Context = 32768  } }
                @{ Name = '64k';  Parameters = @{ Context = 65536  } }
                @{ Name = '96k';  Parameters = @{ Context = 98304  } }
                @{ Name = '128k'; Parameters = @{ Context = 131072 } }
            )

            Variants = @(
                @{ Name = 'ple16-allocation-nomtp'; Parameters = @{} }
            )
        }
    )
}
