# ROCm b12188: 64k code PP, all HIP RGP host/dispatch markers disabled.
# Compare old IQ3, old IQ4, updated new IQ3 at ub512 and ub1024 (6 runs).
# Same fixed 64k code input, CLI arguments and runtime build as prior RGP captures.
# Order is reversible by ubatch to reduce a monotonic time-order confound:
#   ub512: old IQ3 -> old IQ4 -> new IQ3
#   ub1024: new IQ3 -> old IQ4 -> old IQ3
# Model MHHNewIQ3 is the PLE16-converted updated Unsloth UD-IQ3_XXS.
# Execution must NOT have Radeon GPU Profiler capture enabled.
@{
    SchemaVersion = 1
    Name = 'qwen38-r6-rocm-pp64k-marker-off-oldiq3-oldiq4-newiq3-6run-20261112'
    Settings = @{
        CooldownSeconds = 45
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
            GenerationTokens = 256
            PromptCacheMiB = 0
            Temperature = 0.0
            TopP = 0.8
            Reasoning = 'off'
            Fit = 'on'
            Mtp = $false
            ResourceMonitor = $true
            ExtraArgs = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--top-k', '20', '--min-p', '0.05')
        }
        Environment = @{
            QWEN4EXP_QSA_GATHER = '0'
            GGML_VK_QSA_UNION = '0'
            GGML_VK_QSA_UNION_MIN_KV = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER = '0'
            LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'
            LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'
            LLAMA_MTP_EH_PROJ_FLATTEN = '0'
            GGML_HIP_MMQ_TRACE = '0'
            GGML_HIP_MMQ_TRACE_LAYER = $null
            GGML_HIP_MMQ_TRACE_N = $null
            GGML_HIP_FA_TRACE = '0'
            GGML_HIP_FA_TRACE_KV = $null
            GGML_HIP_FA_TRACE_LAYER = $null
            GGML_HIP_RGP_ANCHOR = '0'
            GGML_HIP_RGP_ANCHOR_KV = $null
            GGML_HIP_RGP_FA_SURVEY = '0'
            GGML_HIP_RGP_FA_SURVEY_FINE_BAND = $null
            GGML_HIP_RGP_FA_SURVEY_FINE_LAYER = $null
            LLAMA_EVOX2_RGP_SSE_TRACE = '0'
        }
    }
    Jobs = @(
        @{
            Name = 'pp64k-pponly-oldiq3-ub512'
            Tool = 'cli'
            BuildKeys = @('R6RocmPp64kMmqTrace')
            ModelKeys = @('MHHOldIQ3')
            Parameters = @{ UBatch = 512 }
            Cases = @(@{
                Name = 'code-64k'
                Parameters = @{ Context = 65536; InputKey = 'PPCode64kRgp' }
            })
            Variants = @(@{ Name = 'rgp-clean' })
        },
        @{
            Name = 'pp64k-pponly-oldiq4-ub512'
            Tool = 'cli'
            BuildKeys = @('R6RocmPp64kMmqTrace')
            ModelKeys = @('MHHOldIQ4')
            Parameters = @{ UBatch = 512 }
            Cases = @(@{
                Name = 'code-64k'
                Parameters = @{ Context = 65536; InputKey = 'PPCode64kRgp' }
            })
            Variants = @(@{ Name = 'rgp-clean' })
        },
        @{
            Name = 'pp64k-pponly-newiq3-ub512'
            Tool = 'cli'
            BuildKeys = @('R6RocmPp64kMmqTrace')
            ModelKeys = @('MHHNewIQ3')
            Parameters = @{ UBatch = 512 }
            Cases = @(@{
                Name = 'code-64k'
                Parameters = @{ Context = 65536; InputKey = 'PPCode64kRgp' }
            })
            Variants = @(@{ Name = 'rgp-clean' })
        },
        @{
            Name = 'pp64k-pponly-newiq3-ub1024'
            Tool = 'cli'
            BuildKeys = @('R6RocmPp64kMmqTrace')
            ModelKeys = @('MHHNewIQ3')
            Parameters = @{ UBatch = 1024 }
            Cases = @(@{
                Name = 'code-64k'
                Parameters = @{ Context = 65536; InputKey = 'PPCode64kRgp' }
            })
            Variants = @(@{ Name = 'rgp-clean' })
        },
        @{
            Name = 'pp64k-pponly-oldiq4-ub1024'
            Tool = 'cli'
            BuildKeys = @('R6RocmPp64kMmqTrace')
            ModelKeys = @('MHHOldIQ4')
            Parameters = @{ UBatch = 1024 }
            Cases = @(@{
                Name = 'code-64k'
                Parameters = @{ Context = 65536; InputKey = 'PPCode64kRgp' }
            })
            Variants = @(@{ Name = 'rgp-clean' })
        },
        @{
            Name = 'pp64k-pponly-oldiq3-ub1024'
            Tool = 'cli'
            BuildKeys = @('R6RocmPp64kMmqTrace')
            ModelKeys = @('MHHOldIQ3')
            Parameters = @{ UBatch = 1024 }
            Cases = @(@{
                Name = 'code-64k'
                Parameters = @{ Context = 65536; InputKey = 'PPCode64kRgp' }
            })
            Variants = @(@{ Name = 'rgp-clean' })
        }
    )
}
