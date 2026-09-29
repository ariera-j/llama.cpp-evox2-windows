@{
    SchemaVersion = 1
    Name = 'mtp-qsa-threshold-example'

    Settings = @{
        CooldownSeconds = 10
        ContinueOnError = $true
    }

    Defaults = @{
        CliParameters = @{
            KvType           = 'f16'
            UBatch           = 1024
            Batch            = 2048
            Threads          = 4
            GpuLayers        = 999
            CpuMoe           = 0
            FlashAttn        = '1'
            GenerationTokens = 1024
            PromptCacheMiB   = 0
            Temperature      = 0.2
            TopP             = 0.8
            Reasoning        = 'off'
            Fit              = 'off'
            ResourceMonitor  = $true
        }
    }

    Jobs = @(
        @{
            Name = 'cli-mtp-qsa-threshold'
            Tool = 'cli'

            BuildKeys = @(
                'R3Vulkan'
            )

            ModelKeys = @(
                'UnslothPle16'
            )

            Cases = @(
                @{
                    Name = '128k'
                    Parameters = @{
                        Context       = 131072
                        InputKey      = '128k'
                        Mtp           = $true
                        DraftModelKey = 'UnslothMtp'
                        DraftMax      = 2
                        DraftPMin     = 0.0
                    }
                }
            )

            Variants = @(
                @{
                    Name = 'mtp-qsa-49152'
                    Environment = @{
                        LLAMA_MTP_QSA_MIN_KV = '49152'
                    }
                }
            )
        }
    )
}
