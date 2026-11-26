@{
    SchemaVersion = 1
    Name = 'qwen38-b12651-vulkan-abba'
    Settings = @{ ContinueOnError = $false; CooldownSeconds = 10 }

    Defaults = @{
        Environment = @{
            GGML_VK_PERF_LOGGER = $null
            GGML_VK_PERF_LOGGER_CONCURRENT = $null
            GGML_VK_PERF_LOGGER_FREQUENCY = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE = $null
        }
        BenchParameters = @{
            UmaLabel = 'UMA96GB'
            ResourceMonitor = $true
            Threads = 4
            Batch = 2048
            UBatch = 1024
            GpuLayers = 999
            CpuMoe = 0
            KvType = 'f16'
            FlashAttn = 'on'
            NoWarmup = $false
            Repetitions = 3
        }
    }

    Jobs = @(
        @{
            Name = 'vulkan-graph-opt-abba'
            Tool = 'bench'
            BuildKeys = @('VulkanStage2')
            ModelKeys = @('UnslothPle16')
            Cases = @(@{ Name = 'tg32'; Parameters = @{ PromptTokens = @(0); GenerationTokens = @(32); Depths = @(0) } })
            # The marker distinguishes effective conditions, including the repeated A and B runs.
            Variants = @(
                @{ Name = 'A1'; Environment = @{ EVOX2_ABBA_RUN = 'A1' } },
                @{ Name = 'B1'; Environment = @{ EVOX2_ABBA_RUN = 'B1'; GGML_VK_DISABLE_GRAPH_OPTIMIZE = '1' } },
                @{ Name = 'B2'; Environment = @{ EVOX2_ABBA_RUN = 'B2'; GGML_VK_DISABLE_GRAPH_OPTIMIZE = '1' } },
                @{ Name = 'A2'; Environment = @{ EVOX2_ABBA_RUN = 'A2' } }
            )
        }
    )
}
