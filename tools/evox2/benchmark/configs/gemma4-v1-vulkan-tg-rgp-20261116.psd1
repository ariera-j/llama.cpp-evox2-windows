@{
    SchemaVersion = 1
    Name = 'gemma4-v1-vulkan-tg-rgp-20261116'

    # Diagnostic capture only. Do not compare RGP runs as speed baselines.
    # Requires local.psd1 entries:
    # Builds.Gemma4V1RgpVulkan, Models.Gemma4_31B, Inputs.Gemma4Short.

    Settings = @{
        CooldownSeconds = 0
        ContinueOnError = $false
    }

    Defaults = @{
        CliParameters = @{
            KvType           = 'f16'
            UBatch           = 512
            Batch            = 2048
            Threads          = 4
            GpuLayers        = 999
            CpuMoe           = 0
            FlashAttn        = 'auto'
            Verbosity        = 4
            GenerationTokens = 512
            PromptCacheMiB   = 0
            Temperature      = 0.2
            TopP             = 0.8
            Reasoning        = 'off'
            Fit              = 'on'
            Mtp              = $false
            ResourceMonitor  = $true
            ExtraArgs        = @('-tb', '4', '--ctx-checkpoints', '0t',
                                 '--seed', '1234', '--ignore-eos')
        }
        Environment = @{
            EVOX2_VK_TG_RGP_MARKERS         = '1'
            GGML_VK_DEBUG_MARKERS           = '1'
            GGML_VK_PERF_LOGGER             = $null
            GGML_VK_PERF_LOGGER_CONCURRENT  = $null
            GGML_VK_SYNC_LOGGER             = $null
            GGML_VK_MEMORY_LOGGER           = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE  = $null
            GGML_VK_QSA_UNION               = $null
            GGML_VK_MTP_PP_RGP_MARKERS      = $null
        }
    }

    Jobs = @(
        @{
            Name = 'gemma4-v1-vulkan-tg'
            Tool = 'cli'
            BuildKeys = @('Gemma4V1RgpVulkan')
            ModelKeys = @('Gemma4_31B')
            Cases = @(
                @{
                    Name = 'short-512'
                    Parameters = @{
                        Context = 4096
                        InputKey = 'Gemma4Short'
                        GenerationTokens = 512
                    }
                }
            )
            Variants = @(
                @{ Name = 'rgp-tg-markers' }
            )
        }
    )
}
