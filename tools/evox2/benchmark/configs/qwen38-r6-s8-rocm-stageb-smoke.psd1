@{
    SchemaVersion = 1
    Name = 'qwen38-r6-s8-rocm-stageb-smoke'

    # Optional G8-4 only. Do not run before ROCm baseline/native/4k gates pass.
    # This checks execution, not standalone Draft K/V numerical equivalence.
    Settings = @{
        CooldownSeconds = 5
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
            GenerationTokens = 64
            PromptCacheMiB   = 0
            Temperature      = 0.0
            TopP             = 0.8
            Reasoning        = 'off'
            Fit              = 'off'
            Mtp              = $true
            DraftMax         = 2
            DraftPMin        = 0.0
            ResourceMonitor  = $true
            ExtraArgs        = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--ignore-eos')
        }
        Environment = @{
            GGML_VK_QSA_UNION                 = '0'
            GGML_VK_QSA_UNION_MIN_KV          = '32768'
            GGML_VK_QSA_UNION_STATS           = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER     = '1'
            LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
            LLAMA_MTP_DRAFT_PREFILL_KV_CROP  = '0'
            LLAMA_MTP_EH_PROJ_FLATTEN        = '0'
            LLAMA_QSA_NOOP_TRACE             = $null
            LLAMA_MTP_DIAG                   = $null
            LLAMA_MTP_QSA_MIN_KV             = $null
            LLAMA_GRAPH_REUSE_DISABLE        = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE   = $null
            EVOX2_ABBA_RUN                   = $null
        }
    }

    Jobs = @(
        @{
            Name = 's8-iq3-rocm-stageb-4k'
            Tool = 'cli'
            BuildKeys = @('CombinedROCm')
            ModelKeys = @('UnslothPle16')
            Cases = @(
                @{ Name = '4k'; Parameters = @{ Context = 4096; InputFile = 'tools/evox2/benchmark/inputs/mtp-short.txt'; DraftModelKey = 'UnslothMtp' } }
            )
            Variants = @(
                @{ Name = 'C-stageb-off' }
                @{ Name = 'A-stageb-on';  Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1' } }
                @{ Name = 'B-flatten-on'; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1' } }
            )
        }
    )
}
