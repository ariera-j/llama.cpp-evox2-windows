@{
    SchemaVersion = 1
    Name = 'qwen38-r6-rocm-qsa-rgp-128k-20261102'

    # RGP diagnostic only: ONE 128k real-input, MTP-OFF ROCm run.
    # First-text / every-32-text-delta cues are emitted by the research
    # llama-cli, NOT by the GPU or server. See runbook for capture semantics.
    # Use the separate new research binary, never replace frozen b11908.
    # Do not use this run to infer ordinary PP/TG speed.
    Settings = @{
        CooldownSeconds = 0
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
            ResourceMonitor  = $false
            ExtraArgs        = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--ignore-eos')
        }
        Environment = @{
            # The trace lives in tools/cli/cli-context.cpp, not in HIP.
            LLAMA_EVOX2_RGP_SSE_TRACE       = '1'
            GGML_VK_QSA_UNION                 = '0'
            GGML_VK_QSA_UNION_MIN_KV          = '32768'
            GGML_VK_QSA_UNION_STATS           = $null
            GGML_VK_QSA_UNION_STATS_FILE      = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER     = '0'
            LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'
            LLAMA_MTP_DRAFT_PREFILL_KV_CROP  = '0'
            LLAMA_MTP_EH_PROJ_FLATTEN        = '0'
            LLAMA_QSA_NO_POOLED_CACHE        = $null
            LLAMA_QSA_POOLED_MAX_TOKENS      = $null
            QWEN4EXP_QSA_GATHER              = '0'
            LLAMA_GRAPH_REUSE_DISABLE        = $null
        }
    }

    Jobs = @(
        @{
            Name      = 'rocm-qsa-rgp-tg'
            Tool      = 'cli'
            BuildKeys = @('R6RocmQsaRgp')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k' } }
            )
            Variants = @(
                @{ Name = 'mtp-off-trace' }
            )
        }
    )
}
