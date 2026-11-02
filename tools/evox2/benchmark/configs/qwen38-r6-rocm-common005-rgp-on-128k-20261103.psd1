@{
    SchemaVersion = 1
    Name = 'qwen38-r6-rocm-common005-rgp-on-128k-20261103'

    # Post-COMMON-005 RGP: ONE 128k real-input, Gather ON, MTP OFF.
    # Compare to PRE-patch 2026-11-02 128k RGP capture.
    # Use previously verified b12013 R6RocmCommon005 (NOT R6RocmQsaRgp
    # and NOT stable b11908). Keep the original OFF RGP plan unchanged.
    # SSE text-delta cues are host timestamps, NOT GPU dispatch markers.
    # Measure-LlamaCli.ps1 now prints one TG START line (first text SSE cue)
    # to the benchmark console. Do NOT tail stderr.log live. After TG START,
    # capture steady TG with the same relative 1024-dispatch RGP mode.
    # This run is diagnostic, NOT a regular PP/TG performance baseline.
    # NEVER run unsafe broad HIP FLASH_ATTN_EXT backend tests.
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
            # Host-side SSE cue: read saved log after capture, not live.
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
            QWEN4EXP_QSA_GATHER              = '1'
            LLAMA_GRAPH_REUSE_DISABLE        = $null
        }
    }

    Jobs = @(
        @{
            Name      = 'common005-rgp-on-128k'
            Tool      = 'cli'
            BuildKeys = @('R6RocmCommon005')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k' } }
            )
            Variants = @(
                @{ Name = 'gather-on-mtp-off' }
            )
        }
    )
}
