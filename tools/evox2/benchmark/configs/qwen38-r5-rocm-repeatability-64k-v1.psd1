@{
    SchemaVersion = 1
    Name = 'qwen38-r5-rocm-repeatability-64k-v1'

    # Fresh-process ROCm output-repeatability diagnostic.
    #
    # Goal:
    #   Separate three first-pass hypotheses while keeping model/input/binary/runtime
    #   fixed:
    #     1) baseline ROCm/HIP path
    #     2) Flash Attention disabled
    #     3) HIP_LAUNCH_BLOCKING=1
    #
    # Each matrix run starts a new llama-cli process. This is intentionally NOT the
    # later same-server target/polluter stale-KV test.
    #
    # Required local.psd1 entries:
    #   Builds.R5ROCmRuntimeTheRock10
    #   Models.UnslothPle16
    #   Inputs.64k
    #
    # Measure-LlamaCli.ps1 hashes normalized stdout when --no-display-prompt is active.
    # The normalization removes the variable PP/TG footer line; the remaining
    # stdout contains the generated content plus deterministic CLI framing.
    # matrix-results.csv surfaces OutputFingerprintSha256/status.
    #
    # Execution order is interleaved by repetition to reduce time/order bias:
    #   baseline-r1 -> fa-off-r1 -> hip-blocking-r1 -> ... -> r4

    Settings = @{
        CooldownSeconds = 20
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
            ResourceMonitor  = $true
            ExtraArgs = @(
                '-tb', '4',
                '--ctx-checkpoints', '0t',
                '--seed', '1234',
                '--ignore-eos',
                '--no-display-prompt'
            )
        }

        Environment = @{
            # Repeatability variables / candidate workarounds.
            HIP_LAUNCH_BLOCKING                 = $null
            GGML_CUDA_FA_ZERO_MASKED            = $null

            # Keep unrelated local experiments out of this correctness test.
            LLAMA_MTP_SKIP_DENSE_INDEXER        = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION    = $null
            LLAMA_QSA_NOOP_TRACE                = $null
            LLAMA_MTP_DIAG                      = $null
            LLAMA_QSA_NO_POOLED_CACHE           = $null
            LLAMA_QSA_POOLED_MAX_TOKENS         = $null
            QWEN4EXP_QSA_GATHER                 = $null
            LLAMA_MTP_QSA_MIN_KV                = $null
            GGML_VK_QSA_UNION                   = $null
            GGML_VK_QSA_UNION_MIN_KV            = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE      = $null
            LLAMA_GRAPH_REUSE_DISABLE           = $null
            GGML_VK_FUSE_UNARY_MUL              = $null
            GGML_VK_SHMEM_PAD                   = $null
            GGML_VK_DENSE_WAVE32                = $null
            GGML_VK_PERF_LOGGER                 = $null
            GGML_VK_PERF_LOGGER_FREQUENCY       = $null
            GGML_VK_PERF_LOGGER_CONCURRENT      = $null
            GGML_VK_PERF_GET_ROWS_DETAILS       = $null
            GGML_VK_FORCE_MMVQ                  = $null
            GGML_VK_DISABLE_MMVQ                = $null
            GGML_VK_FA_SPARSE_DISABLE           = $null
            GGML_VK_MOE_TILE_LOG                = $null
            GGML_VK_MOE_LEGACY_TILE_SELECTION   = $null
            GGML_VK_GET_ROWS_128X4              = $null

            ROCM_RUNTIME_VARIANT                = 'therock10-pure'
            ROCM_REPEATABILITY_PHASE            = 'fresh-process-cli-v1'
            ROCM_REPEATABILITY_CASE             = $null
            ROCM_REPEATABILITY_REP              = $null
        }
    }

    Jobs = @(
        @{
            Name = 'rocm-repeatability'
            Tool = 'cli'
            BuildKeys = @('R5ROCmRuntimeTheRock10')
            ModelKeys = @('UnslothPle16')

            Cases = @(
                @{
                    Name = '64k'
                    Parameters = @{
                        Context = 65536
                        InputKey = '64k'
                    }
                }
            )

            Variants = @(
                @{
                    Name = 'baseline-r1'
                    Parameters = @{ FlashAttn = 'auto' }
                    Environment = @{
                        HIP_LAUNCH_BLOCKING = $null
                        ROCM_REPEATABILITY_CASE = 'baseline'
                        ROCM_REPEATABILITY_REP = '1'
                    }
                },
                @{
                    Name = 'fa-off-r1'
                    Parameters = @{ FlashAttn = 'off' }
                    Environment = @{
                        HIP_LAUNCH_BLOCKING = $null
                        ROCM_REPEATABILITY_CASE = 'fa-off'
                        ROCM_REPEATABILITY_REP = '1'
                    }
                },
                @{
                    Name = 'hip-blocking-r1'
                    Parameters = @{ FlashAttn = 'auto' }
                    Environment = @{
                        HIP_LAUNCH_BLOCKING = '1'
                        ROCM_REPEATABILITY_CASE = 'hip-launch-blocking'
                        ROCM_REPEATABILITY_REP = '1'
                    }
                },

                @{
                    Name = 'baseline-r2'
                    Parameters = @{ FlashAttn = 'auto' }
                    Environment = @{
                        HIP_LAUNCH_BLOCKING = $null
                        ROCM_REPEATABILITY_CASE = 'baseline'
                        ROCM_REPEATABILITY_REP = '2'
                    }
                },
                @{
                    Name = 'fa-off-r2'
                    Parameters = @{ FlashAttn = 'off' }
                    Environment = @{
                        HIP_LAUNCH_BLOCKING = $null
                        ROCM_REPEATABILITY_CASE = 'fa-off'
                        ROCM_REPEATABILITY_REP = '2'
                    }
                },
                @{
                    Name = 'hip-blocking-r2'
                    Parameters = @{ FlashAttn = 'auto' }
                    Environment = @{
                        HIP_LAUNCH_BLOCKING = '1'
                        ROCM_REPEATABILITY_CASE = 'hip-launch-blocking'
                        ROCM_REPEATABILITY_REP = '2'
                    }
                },

                @{
                    Name = 'baseline-r3'
                    Parameters = @{ FlashAttn = 'auto' }
                    Environment = @{
                        HIP_LAUNCH_BLOCKING = $null
                        ROCM_REPEATABILITY_CASE = 'baseline'
                        ROCM_REPEATABILITY_REP = '3'
                    }
                },
                @{
                    Name = 'fa-off-r3'
                    Parameters = @{ FlashAttn = 'off' }
                    Environment = @{
                        HIP_LAUNCH_BLOCKING = $null
                        ROCM_REPEATABILITY_CASE = 'fa-off'
                        ROCM_REPEATABILITY_REP = '3'
                    }
                },
                @{
                    Name = 'hip-blocking-r3'
                    Parameters = @{ FlashAttn = 'auto' }
                    Environment = @{
                        HIP_LAUNCH_BLOCKING = '1'
                        ROCM_REPEATABILITY_CASE = 'hip-launch-blocking'
                        ROCM_REPEATABILITY_REP = '3'
                    }
                },

                @{
                    Name = 'baseline-r4'
                    Parameters = @{ FlashAttn = 'auto' }
                    Environment = @{
                        HIP_LAUNCH_BLOCKING = $null
                        ROCM_REPEATABILITY_CASE = 'baseline'
                        ROCM_REPEATABILITY_REP = '4'
                    }
                },
                @{
                    Name = 'fa-off-r4'
                    Parameters = @{ FlashAttn = 'off' }
                    Environment = @{
                        HIP_LAUNCH_BLOCKING = $null
                        ROCM_REPEATABILITY_CASE = 'fa-off'
                        ROCM_REPEATABILITY_REP = '4'
                    }
                },
                @{
                    Name = 'hip-blocking-r4'
                    Parameters = @{ FlashAttn = 'auto' }
                    Environment = @{
                        HIP_LAUNCH_BLOCKING = '1'
                        ROCM_REPEATABILITY_CASE = 'hip-launch-blocking'
                        ROCM_REPEATABILITY_REP = '4'
                    }
                }
            )
        }
    )
}
