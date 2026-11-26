@{
 SchemaVersion=1
 Name='adrenalin-pre-cli-20261126'
 Settings=@{ContinueOnError=$false;CooldownSeconds=5;SafetyGate=@{MinimumAvailableGiB=16;MaxCommitGrowthGiB=4;MaxGpuGrowthGiB=4;PMode='Performance'}}
 Defaults=@{
         Environment = @{
            LLAMA_MODEL_LOAD_DIAG = $null
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
 CliParameters=@{
  UmaLabel='UMA96GB'; Batch=2048; UBatch=1024; Threads=4; GpuLayers=999; CpuMoe=0; KvType='f16'; FlashAttn='auto'
  Verbosity=4; GenerationTokens=256; PromptCacheMiB=0; Temperature=0; TopP=0.8; Reasoning='off';Fit='off';Mtp=$false
  ExtraArgs=@('--seed','1234','--ctx-checkpoints','0','--no-display-prompt')
  ResourceMonitor=$true;ResourceIntervalSeconds=2;AdlxIntervalMs=2000;AdlxMonitorExe='C:/REPLACE/adlx/evox2-adlx-gpu-monitor.exe'
  CapturePhaseMarkers=$true;RamDetail=$true;RamDetailIntervalMs=250;RamDetailPreSeconds=3;RamDetailPostSeconds=5;RamDetailPeakThresholdMiB=64;RamDetailRecoveryToleranceMiB=128
 }
 }
 Jobs=@(
@{Name='cell-2';Tool='cli';BuildKeys=@('Vulkan54');ModelKeys=@('UnslothPle16');Cases=@(@{Name='128k';Parameters=@{Context=131072;InputKey='128k'}})},
@{Name='cell-3';Tool='cli';BuildKeys=@('Vulkan54');ModelKeys=@('AgentionRocmFp4FastPle16');Cases=@(@{Name='64k';Parameters=@{Context=65536;InputKey='64k'}})},
@{Name='cell-4';Tool='cli';BuildKeys=@('Vulkan54');ModelKeys=@('Gemma31B');Cases=@(@{Name='32k';Parameters=@{Context=32768;InputKey='32k'}})},
@{Name='cell-5';Tool='cli';BuildKeys=@('Rocm54');ModelKeys=@('Gemma31B');Cases=@(@{Name='32k';Parameters=@{Context=32768;InputKey='32k'}})},
@{Name='cell-6';Tool='cli';BuildKeys=@('Rocm54');ModelKeys=@('UnslothPle16');Cases=@(@{Name='64k';Parameters=@{Context=65536;InputKey='64k'}})}
)
}
