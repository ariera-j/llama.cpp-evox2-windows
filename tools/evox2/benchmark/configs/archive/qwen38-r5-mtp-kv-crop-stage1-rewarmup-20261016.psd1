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
            LLAMA_MTP_TARGET_REWARMUP            = $null
            LLAMA_MTP_KV_CROP_DIAG             = $null
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
                @{ Name = 'A-short'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0' } }
                @{ Name = 'B-short'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1' } }
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
                @{ Name = 'A1'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; EVOX2_ABBA_RUN = 'B1' } }
                @{ Name = 'B2'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; EVOX2_ABBA_RUN = 'B2' } }
                @{ Name = 'A2'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'; EVOX2_ABBA_RUN = 'A2' } }
            )
        }
        @{
            Name = 'stage1-diag-short'
            Tool = 'cli'
            BuildKeys = @('R5MtpKvCropDiagVulkan')
            ModelKeys = @('UnslothPle16')
            # Instrumentation is opt-in for this job only: never use this
            # diagnostic job for timings or interpret its PP/TG as a speed test.
            Environment = @{
                LLAMA_MTP_KV_CROP_DIAG = '1'
                GGML_VK_QSA_UNION = '1'
                GGML_VK_QSA_UNION_MIN_KV = '32768'
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
                @{ Name = 'A-diag'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0' } }
                @{ Name = 'B-diag'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1' } }
            )
        }
        @{
            Name = 'stage1-kv-only-diag-short'
            Tool = 'cli'
            BuildKeys = @('R5MtpKvOnlyVulkan')
            ModelKeys = @('UnslothPle16')
            # v2 active-graph instrumentation: functionality only, NOT timings.
            Environment = @{
                LLAMA_MTP_KV_CROP_DIAG = '1'
                GGML_VK_QSA_UNION = '1'
                GGML_VK_QSA_UNION_MIN_KV = '32768'
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
                @{ Name = 'A-diag'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0' } }
                @{ Name = 'B-diag'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1' } }
            )
        }
        @{
            Name = 'stage1-kv-only-64k'
            Tool = 'cli'
            BuildKeys = @('R5MtpKvOnlyVulkan')
            ModelKeys = @('UnslothPle16')
            # Stage-B speed cohort: diagnostics unset in Defaults.Environment.
            Environment = @{ GGML_VK_QSA_UNION = '1'; GGML_VK_QSA_UNION_MIN_KV = '32768' }
            Cases = @(@{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k' } })
            Variants = @(
                @{ Name = 'A1'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; EVOX2_ABBA_RUN = 'B1' } }
                @{ Name = 'B2'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; EVOX2_ABBA_RUN = 'B2' } }
                @{ Name = 'A2'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'; EVOX2_ABBA_RUN = 'A2' } }
            )
        }
        @{
            Name = 'stage1-kv-only-128k'
            Tool = 'cli'
            BuildKeys = @('R5MtpKvOnlyVulkan')
            ModelKeys = @('UnslothPle16')
            # Stage-B 128k reference: MTP remains ON in both variants.
            # Keep these conditions aligned with the MTP-OFF job below.
            Environment = @{ GGML_VK_QSA_UNION = '1'; GGML_VK_QSA_UNION_MIN_KV = '32768' }
            Cases = @(@{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k' } })
            Variants = @(
                @{ Name = 'A'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0' } }
                @{ Name = 'B'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1' } }
            )
        }
        @{
            Name = 'stage1-kv-only-128k-abba'
            Tool = 'cli'
            BuildKeys = @('R5MtpKvOnlyVulkan')
            ModelKeys = @('UnslothPle16')
            # Oct 15 P-MODE/ADLX-controlled Stage-B recheck.
            # Same retained b11618 binary and 128k workload as the earlier A/B,
            # extended to counterbalanced A1/B1/B2/A2. MTP stays ON in both arms.
            # Use the r5-mainline ADLX/P-MODE-aware benchmark wrappers in the
            # local working tree; do not enable graph/RGP diagnostics for timing.
            Environment = @{ GGML_VK_QSA_UNION = '1'; GGML_VK_QSA_UNION_MIN_KV = '32768' }
            Cases = @(@{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k' } })
            Variants = @(
                @{ Name = 'A1'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; EVOX2_ABBA_RUN = 'B1' } }
                @{ Name = 'B2'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; EVOX2_ABBA_RUN = 'B2' } }
                @{ Name = 'A2'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'; EVOX2_ABBA_RUN = 'A2' } }
            )
        }
        @{
            Name = 'stage1-target-rewarmup-short'
            Tool = 'cli'
            BuildKeys = @('R5MtpTargetRewarmVulkan')
            ModelKeys = @('UnslothPle16')
            # Same new binary in both arms. Stage-B stays ON; only the target
            # post-NextN re-warmup switch changes.
            Environment = @{
                LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'
                GGML_VK_QSA_UNION               = '1'
                GGML_VK_QSA_UNION_MIN_KV        = '32768'
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
                @{ Name = 'A-rewarm-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_TARGET_REWARMUP = '0' } }
                @{ Name = 'B-rewarm-on';  Parameters = @{}; Environment = @{ LLAMA_MTP_TARGET_REWARMUP = '1' } }
            )
        }
        @{
            Name = 'stage1-target-rewarmup-64k-abba'
            Tool = 'cli'
            BuildKeys = @('R5MtpTargetRewarmVulkan')
            ModelKeys = @('UnslothPle16')
            Environment = @{
                LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'
                GGML_VK_QSA_UNION               = '1'
                GGML_VK_QSA_UNION_MIN_KV        = '32768'
            }
            Cases = @(@{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k' } })
            Variants = @(
                @{ Name = 'A1-rewarm-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_TARGET_REWARMUP = '0'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1-rewarm-on';  Parameters = @{}; Environment = @{ LLAMA_MTP_TARGET_REWARMUP = '1'; EVOX2_ABBA_RUN = 'B1' } }
                @{ Name = 'B2-rewarm-on';  Parameters = @{}; Environment = @{ LLAMA_MTP_TARGET_REWARMUP = '1'; EVOX2_ABBA_RUN = 'B2' } }
                @{ Name = 'A2-rewarm-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_TARGET_REWARMUP = '0'; EVOX2_ABBA_RUN = 'A2' } }
            )
        }
        @{
            Name = 'stage1-target-rewarmup-128k-abba'
            Tool = 'cli'
            BuildKeys = @('R5MtpTargetRewarmVulkan')
            ModelKeys = @('UnslothPle16')
            Environment = @{
                LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'
                GGML_VK_QSA_UNION               = '1'
                GGML_VK_QSA_UNION_MIN_KV        = '32768'
            }
            Cases = @(@{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k' } })
            Variants = @(
                @{ Name = 'A1-rewarm-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_TARGET_REWARMUP = '0'; EVOX2_ABBA_RUN = 'A1' } }
                @{ Name = 'B1-rewarm-on';  Parameters = @{}; Environment = @{ LLAMA_MTP_TARGET_REWARMUP = '1'; EVOX2_ABBA_RUN = 'B1' } }
                @{ Name = 'B2-rewarm-on';  Parameters = @{}; Environment = @{ LLAMA_MTP_TARGET_REWARMUP = '1'; EVOX2_ABBA_RUN = 'B2' } }
                @{ Name = 'A2-rewarm-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_TARGET_REWARMUP = '0'; EVOX2_ABBA_RUN = 'A2' } }
            )
        }
        @{
            Name = 'stage1-kv-only-128k-mtp-off'
            Tool = 'cli'
            BuildKeys = @('R5MtpKvOnlyVulkan')
            ModelKeys = @('UnslothPle16')
            # Same b11618, main model, input, context and QSA settings as the
            # Stage-B 128k A/B. Fully disable MTP: Mtp=$false alone is not
            # enough because inherited DraftModelKey triggers a harness error.
            Parameters = @{
                Mtp           = $false
                DraftModelKey = ''
            }
            Environment = @{
                GGML_VK_QSA_UNION               = '1'
                GGML_VK_QSA_UNION_MIN_KV        = '32768'
                LLAMA_MTP_DRAFT_PREFILL_KV_CROP = $null
                LLAMA_MTP_KV_CROP_DIAG          = $null
            }
            Cases = @(@{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k' } })
            Variants = @(
                @{ Name = 'MTP-off'; Parameters = @{}; Environment = @{} }
            )
        }
    )
}
