@{
    SchemaVersion = 1
    Name = 'b12651-monitor-overhead'
    Settings = @{
        ContinueOnError = $false
        CooldownSeconds = 5
        SafetyGate = @{ MinimumAvailableGiB = 16; MaxCommitGrowthGiB = 4; MaxGpuGrowthGiB = 4; PMode = 'Performance' }
    }
    Defaults = @{
        Environment = @{
            LLAMA_MODEL_LOAD_DIAG = '1'
            GGML_VK_IQ2_S_MATVEC_A1 = $null
            GGML_VK_IQ2_S_MATVEC_A2 = $null
            GGML_VK_PERF_LOGGER = $null
            GGML_VK_PERF_LOGGER_CONCURRENT = $null
            GGML_VK_PERF_LOGGER_FREQUENCY = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE = $null
            GGML_VK_FORCE_MMVQ = $null
            GGML_VK_DISABLE_MMVQ = $null
            GGML_VK_FUSE_UNARY_MUL = $null
            GGML_VK_GET_ROWS_128X4 = $null
            GGML_VK_QSA_UNION = $null
            LLAMA_EVOX2_RGP_SSE_TRACE = $null
            LLAMA_MTP_DIAG = $null
        }
        BenchParameters = @{
            UmaLabel = 'UMA96GB'; ExpectedBackend='Vulkan'
            PromptTokens=@(8192); GenerationTokens=@(256); Depths=@(0); Repetitions=1
            Threads=4; Batch=2048; UBatch=1024; GpuLayers=999; CpuMoe=0; KvType='f16'; FlashAttn='on'
            NoWarmup=$false; CapturePhaseMarkers=$true
            ExtraArgs=@('--device','Vulkan0','--progress','--verbose')
            ResourceIntervalSeconds=2; AdlxIntervalMs=2000; AdlxMonitorExe='C:/REPLACE/adlx/evox2-adlx-gpu-monitor.exe'; BackgroundIntervalSeconds=15
            RamDetailPreSeconds=3; RamDetailPostSeconds=5; RamDetailPeakThresholdMiB=64; RamDetailRecoveryToleranceMiB=128
        }
    }
    Jobs = @(
        @{
            Name='iq3-pp8192-tg256'; Tool='bench'; BuildKeys=@('VulkanStage2'); ModelKeys=@('UnslothPle16')
            Comparison=@{
                Group='monitoring'; Base='A'; References=@('B','C'); Runs=3; Order='Explicit'
                Rounds=@(
                    @{ Order=@('A','B','C','D') },
                    @{ Order=@('D','C','B','A') },
                    @{ Order=@('B','D','A','C') }
                )
            }
            Variants=@(
                @{ Name='A'; Parameters=@{ ResourceMonitor=$false; NoAdlxMonitor=$true; RamDetail=$false } },
                @{ Name='B'; Parameters=@{ ResourceMonitor=$true; NoAdlxMonitor=$false; RamDetail=$false } },
                @{ Name='C'; Parameters=@{ ResourceMonitor=$true; NoAdlxMonitor=$false; RamDetail=$true; RamDetailIntervalMs=250 } },
                @{ Name='D'; Parameters=@{ ResourceMonitor=$true; NoAdlxMonitor=$false; RamDetail=$true; RamDetailIntervalMs=100 } }
            )
        }
    )
}
