@{
    SchemaVersion = 1
    Name = 'qsa-union-thresholds-example'

    Settings = @{
        CooldownSeconds = 10
        ContinueOnError = $true
    }

    Defaults = @{
        BenchParameters = @{
            KvType          = 'f16'
            UBatch          = 1024
            Batch           = 2048
            Threads         = 4
            GpuLayers       = 999
            CpuMoe          = 0
            FlashAttn       = 'on'
            Repetitions     = 3
            ResourceMonitor = $true
        }
    }

    Jobs = @(
        @{
            Name = 'bench-qsa-union-threshold'
            Tool = 'bench'

            BuildKeys = @(
                'R3Vulkan'
            )

            ModelKeys = @(
                'UnslothPle16'
            )

            Cases = @(
                @{
                    Name = 'pp128k'
                    Parameters = @{
                        PromptTokens     = @(131072)
                        GenerationTokens = @(0)
                        Depths           = @(0)
                    }
                }
            )

            Variants = @(
                @{
                    Name = 'min-kv-26624'
                    Environment = @{
                        GGML_VK_QSA_UNION_MIN_KV = '26624'
                    }
                }
                @{
                    Name = 'min-kv-32768'
                    Environment = @{
                        GGML_VK_QSA_UNION_MIN_KV = '32768'
                    }
                }
            )
        }
    )
}
