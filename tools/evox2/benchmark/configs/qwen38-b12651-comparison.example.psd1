@{
    SchemaVersion = 1
    Name = 'qwen38-b12651-comparison'
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
        CliParameters = @{
            UmaLabel = 'UMA96GB'
            ResourceMonitor = $true
            Threads = 4
            ExtraArgs = @('-tb', '4')
            Batch = 2048
            UBatch = 1024
            GpuLayers = 999
            CpuMoe = 0
            KvType = 'f16'
            FlashAttn = 'on'
            Mtp = $false
            PromptCacheMiB = 0
        }
    }

    Jobs = @(
        @{
            Name = 'bench-backends-iq3'
            Tool = 'bench'
            BuildKeys = @('VulkanCommon001', 'RocmCommon001')
            ModelKeys = @('UnslothPle16')
            Cases = @(@{ Name = 'tg32'; Parameters = @{ PromptTokens = @(0); GenerationTokens = @(32); Depths = @(0) } })
        },
        @{
            Name = 'bench-vulkan-models'
            Tool = 'bench'
            BuildKeys = @('VulkanStage2')
            ModelKeys = @('UnslothPle16', 'AgentionRocmFp4FastPle16')
            Cases = @(@{ Name = 'tg32'; Parameters = @{ PromptTokens = @(0); GenerationTokens = @(32); Depths = @(0) } })
        },
        @{
            Name = 'cli-vulkan-real-input'
            Tool = 'cli'
            BuildKeys = @('VulkanStage2')
            ModelKeys = @('UnslothPle16', 'AgentionRocmFp4FastPle16')
            Cases = @(@{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k'; GenerationTokens = 32 } })
        }
    )
}
