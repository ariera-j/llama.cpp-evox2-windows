@{
    SchemaVersion = 1
    Name = 'qwen38-r5-mtp-draft-kv-parity'

    # Correctness-only diagnostic. llama_state_seq_save_file() explicitly
    # synchronizes and copies the Draft state to disk. NEVER use PP/TG from
    # these jobs to claim performance. Each run produces raw .bin snapshots
    # in the directory shown by mtp_kv_snapshot_v1 (normally <cwd>/kv-parity-output).
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
            ExtraArgs        = @('-tb', '4', '--ctx-checkpoints', '0t',
                                 '--seed', '1234', '--ignore-eos')
        }
        Environment = @{
            GGML_VK_QSA_UNION                 = '1'
            GGML_VK_QSA_UNION_MIN_KV          = '32768'

            LLAMA_MTP_KV_SNAPSHOT_DIR        = $null
            LLAMA_MTP_KV_SNAPSHOT_TAG        = $null
            LLAMA_MTP_KV_SNAPSHOT_POSITIONS  = $null
            LLAMA_MTP_DRAFT_PREFILL_KV_CROP  = $null
            LLAMA_MTP_EH_PROJ_FLATTEN        = $null

            LLAMA_MTP_KV_CROP_DIAG            = $null
            LLAMA_MTP_PP_TRACE                = $null
            LLAMA_MTP_DIAG                    = $null
            LLAMA_MTP_SKIP_DENSE_INDEXER      = $null
            LLAMA_QSA_SKIP_NOOP_INVALIDATION  = $null
            GGML_VK_QSA_UNION_STATS            = $null
            GGML_VK_PERF_LOGGER                = $null
            GGML_VK_PERF_LOGGER_CONCURRENT     = $null
            GGML_VK_DEBUG_MARKERS              = $null
            GGML_VK_MTP_PP_RGP_MARKERS         = $null
            GGML_VK_MTP_PP_RGP_DISPATCH_TRACE  = $null
            GGML_VK_DISABLE_GRAPH_OPTIMIZE     = $null
            LLAMA_GRAPH_REUSE_DISABLE          = $null
            LLAMA_MTP_QSA                      = $null
            LLAMA_MTP_QSA_MIN_KV               = $null
        }
    }

    Jobs = @(
        @{
            Name = 'kv-short'
            Tool = 'cli'
            BuildKeys = @('R5MtpKvParityVulkan')
            ModelKeys = @('UnslothPle16')
            Environment = @{
                LLAMA_MTP_KV_SNAPSHOT_DIR       = 'kv-parity-output/short'
                LLAMA_MTP_KV_SNAPSHOT_POSITIONS = '1'
            }
            Cases = @(@{
                Name = 'smoke'
                Parameters = @{
                    Context          = 32768
                    InputFile        = 'tools\evox2\benchmark\inputs\mtp-short.txt'
                    GenerationTokens = 32
                }
            })
            Variants = @(
                @{ Name = 'C-stageb-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'; LLAMA_MTP_EH_PROJ_FLATTEN = '0'; LLAMA_MTP_KV_SNAPSHOT_TAG = 'C' } }
                @{ Name = 'A-stageb-on-flat-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '0'; LLAMA_MTP_KV_SNAPSHOT_TAG = 'A' } }
                @{ Name = 'B-stageb-on-flat-on'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1'; LLAMA_MTP_KV_SNAPSHOT_TAG = 'B' } }
            )
        }
        @{
            Name = 'kv-64k'
            Tool = 'cli'
            BuildKeys = @('R5MtpKvParityVulkan')
            ModelKeys = @('UnslothPle16')
            Environment = @{
                LLAMA_MTP_KV_SNAPSHOT_DIR       = 'kv-parity-output/64k'
                LLAMA_MTP_KV_SNAPSHOT_POSITIONS = '1024,32768,61789'
            }
            Cases = @(@{ Name = '64k'; Parameters = @{ Context = 65536; InputKey = '64k' } })
            Variants = @(
                @{ Name = 'C-stageb-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'; LLAMA_MTP_EH_PROJ_FLATTEN = '0'; LLAMA_MTP_KV_SNAPSHOT_TAG = 'C' } }
                @{ Name = 'A-stageb-on-flat-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '0'; LLAMA_MTP_KV_SNAPSHOT_TAG = 'A' } }
                @{ Name = 'B-stageb-on-flat-on'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1'; LLAMA_MTP_KV_SNAPSHOT_TAG = 'B' } }
            )
        }
        @{
            Name = 'kv-128k'
            Tool = 'cli'
            BuildKeys = @('R5MtpKvParityVulkan')
            ModelKeys = @('UnslothPle16')
            Environment = @{
                LLAMA_MTP_KV_SNAPSHOT_DIR       = 'kv-parity-output/128k'
                LLAMA_MTP_KV_SNAPSHOT_POSITIONS = '32768,65536,126253'
            }
            Cases = @(@{ Name = '128k'; Parameters = @{ Context = 131072; InputKey = '128k' } })
            Variants = @(
                @{ Name = 'C-stageb-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'; LLAMA_MTP_EH_PROJ_FLATTEN = '0'; LLAMA_MTP_KV_SNAPSHOT_TAG = 'C' } }
                @{ Name = 'A-stageb-on-flat-off'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '0'; LLAMA_MTP_KV_SNAPSHOT_TAG = 'A' } }
                @{ Name = 'B-stageb-on-flat-on'; Parameters = @{}; Environment = @{ LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'; LLAMA_MTP_EH_PROJ_FLATTEN = '1'; LLAMA_MTP_KV_SNAPSHOT_TAG = 'B' } }
            )
        }
    )
}
