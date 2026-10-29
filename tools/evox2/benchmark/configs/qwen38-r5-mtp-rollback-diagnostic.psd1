@{
    SchemaVersion = 1
    Name = 'qwen38-r5-mtp-rollback-diagnostic'

    # Correctness diagnostics only! Synthetic speculative acceptance deliberately
    # replaces real verification, so synthetic outputs are NOT genuine model
    # outputs. Compare only same-scenario C/A/B, and inspect event coverage.
    Settings = @{
        CooldownSeconds = 10
        ContinueOnError = $false
    }

    Defaults = @{
        CliParameters = @{
            KvType = 'f16'
            UBatch = 1024
            Batch = 2048
            Threads = 4
            GpuLayers = 999
            CpuMoe = 0
            FlashAttn = 'auto'
            Verbosity = 4
            GenerationTokens = 128
            PromptCacheMiB = 0
            Temperature = 0.0
            TopP = 0.8
            Reasoning = 'off'
            Fit = 'off'
            Mtp = $true
            DraftModelKey = 'UnslothMtp'
            DraftMax = 2
            DraftPMin = 0.0
            ResourceMonitor = $true
            # Each scenario below supplies its own full ExtraArgs list.
            ExtraArgs = @('-tb', '4', '--ctx-checkpoints', '0t',
                          '--seed', '1234', '--ignore-eos')
        }
        Environment = @{
            GGML_VK_QSA_UNION                 = '1'
            GGML_VK_QSA_UNION_MIN_KV          = '32768'
            LLAMA_MTP_DRAFT_PREFILL_KV_CROP  = $null
            LLAMA_MTP_EH_PROJ_FLATTEN        = $null

            LLAMA_MTP_ROLLBACK_DIAG           = '1'
            LLAMA_MTP_ROLLBACK_FORCE_CKPT     = '0'
            LLAMA_MTP_ROLLBACK_TAG            = $null
            LLAMA_MTP_KV_SNAPSHOT_DIR         = $null
            LLAMA_MTP_KV_SNAPSHOT_TAG         = $null
            LLAMA_MTP_KV_SNAPSHOT_POSITIONS   = $null
            LLAMA_MTP_PP_TRACE               = $null
            LLAMA_MTP_KV_CROP_DIAG           = $null
            LLAMA_MTP_DIAG                   = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER     = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION = $null
            GGML_VK_MTP_PP_RGP_MARKERS       = $null
            GGML_VK_MTP_PP_RGP_DISPATCH_TRACE = $null
            GGML_VK_QSA_UNION_STATS          = $null
            GGML_VK_PERF_LOGGER              = $null
            GGML_VK_PERF_LOGGER_CONCURRENT   = $null
            LLAMA_MTP_QSA                    = $null
            LLAMA_MTP_QSA_MIN_KV             = $null
        }
    }

    Jobs = @(
        @{
            Name = 'rollback-short'
            Tool = 'cli'
            BuildKeys = @('R5MtpRollbackVulkan')
            ModelKeys = @('UnslothPle16')

            Cases = @(
                @{
                    Name = 'natural'
                    Parameters = @{
                        Context = 32768
                        InputFile = 'tools\evox2\benchmark\inputs\mtp-short.txt'
                        GenerationTokens = 128
                        ExtraArgs = @('-tb','4','--ctx-checkpoints','0t',
                                      '--seed','1234','--ignore-eos')
                    }
                    Environment = @{ LLAMA_MTP_ROLLBACK_FORCE_CKPT = '0' }
                }
                @{
                    Name = 'reject-zero'
                    Parameters = @{
                        Context = 32768
                        InputFile = 'tools\evox2\benchmark\inputs\mtp-short.txt'
                        GenerationTokens = 128
                        ExtraArgs = @('-tb','4','--ctx-checkpoints','0t',
                                      '--seed','1234','--ignore-eos',
                                      '--spec-synth-rates','0,0')
                    }
                    Environment = @{ LLAMA_MTP_ROLLBACK_FORCE_CKPT = '1' }
                }
                @{
                    Name = 'reject-after-one'
                    Parameters = @{
                        Context = 32768
                        InputFile = 'tools\evox2\benchmark\inputs\mtp-short.txt'
                        GenerationTokens = 128
                        ExtraArgs = @('-tb','4','--ctx-checkpoints','0t',
                                      '--seed','1234','--ignore-eos',
                                      '--spec-synth-rates','1,0')
                    }
                    Environment = @{ LLAMA_MTP_ROLLBACK_FORCE_CKPT = '1' }
                }
                @{
                    Name = 'accept-all'
                    Parameters = @{
                        Context = 32768
                        InputFile = 'tools\evox2\benchmark\inputs\mtp-short.txt'
                        GenerationTokens = 128
                        ExtraArgs = @('-tb','4','--ctx-checkpoints','0t',
                                      '--seed','1234','--ignore-eos',
                                      '--spec-synth-rates','1,1')
                    }
                    Environment = @{ LLAMA_MTP_ROLLBACK_FORCE_CKPT = '1' }
                }
            )
            Variants = @(
                @{ Name = 'C'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'; LLAMA_MTP_EH_PROJ_FLATTEN = '0'; LLAMA_MTP_ROLLBACK_TAG = 'C' } }
                @{ Name = 'A'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '0'; LLAMA_MTP_ROLLBACK_TAG = 'A' } }
                @{ Name = 'B'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1'; LLAMA_MTP_ROLLBACK_TAG = 'B' } }
            )
        }
        @{
            Name = 'rollback-64k'
            Tool = 'cli'
            BuildKeys = @('R5MtpRollbackVulkan')
            ModelKeys = @('UnslothPle16')

            Cases = @(
                @{
                    Name = 'natural'
                    Parameters = @{
                        Context = 65536
                        InputKey = '64k'
                        GenerationTokens = 128
                        ExtraArgs = @('-tb','4','--ctx-checkpoints','0t',
                                      '--seed','1234','--ignore-eos')
                    }
                    Environment = @{ LLAMA_MTP_ROLLBACK_FORCE_CKPT = '0' }
                }
                @{
                    Name = 'reject-after-one'
                    Parameters = @{
                        Context = 65536
                        InputKey = '64k'
                        GenerationTokens = 128
                        ExtraArgs = @('-tb','4','--ctx-checkpoints','0t',
                                      '--seed','1234','--ignore-eos',
                                      '--spec-synth-rates','1,0')
                    }
                    Environment = @{ LLAMA_MTP_ROLLBACK_FORCE_CKPT = '1' }
                }
            )
            Variants = @(
                @{ Name = 'C'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'; LLAMA_MTP_EH_PROJ_FLATTEN = '0'; LLAMA_MTP_ROLLBACK_TAG = 'C' } }
                @{ Name = 'A'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '0'; LLAMA_MTP_ROLLBACK_TAG = 'A' } }
                @{ Name = 'B'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1'; LLAMA_MTP_ROLLBACK_TAG = 'B' } }
            )
        }
    )
}
