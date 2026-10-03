@{
    # Copy this file to local.psd1 and edit local.psd1.
    # local.psd1 is ignored by Git.

    RepoRoot = 'C:\llama-build\llama.cpp-evox2-windows-r4'
    # Empty uses evox2-logs under the scripts' actual worktree automatically.
    # An explicit path is honored, including a path copied from another worktree.
    LogRoot  = ''

    # Manual test-condition label. This is intentionally not auto-detected.
    UmaLabel = '96GB'

    Builds = @{
        R4Vulkan = @{
            BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r4\build-vulkan-r4\bin\Release'
            ExpectedBackend = 'Vulkan'
        }

        # Optional PP MoE tile-selection diagnostic build; preserves R4Vulkan.
        R4MoeTileVulkan = @{
            BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r4\build-vulkan-r4-moe-tile\bin\Release'
            ExpectedBackend = 'Vulkan'
        }

        R4ROCm = @{
            BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r4\build-rocm-r4\bin\Release'
            ExpectedBackend = 'ROCm'
        }
    }

    # Historical r3 plans use R3*/Common004*/Common005* build keys.
    # Add those keys explicitly, pointing at the preserved r3 builds, if needed.

    Models = @{
        # Primary r4 baseline: original GGUF with joined PLE tensor layout.
        # Use shard 00001; this does not require joining GGUF files physically.
        UnslothOriginal = @{
            Path  = 'C:\path\to\Qwen3.8-Flash-Next-UD-IQ3_XXS-00001-of-00003.gguf'
            Alias = 'unsloth-original'
        }

        UnslothPle16 = @{
            Path  = 'C:\path\to\Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf'
            Alias = 'unsloth-ple16'
        }

        UnslothMtp = @{
            Path  = 'C:\path\to\mtp-Qwen3.8-Flash-Next-Q8_0.gguf'
            Alias = 'unsloth-mtp-q8_0'
        }
    }

    Inputs = @{
        '32k'  = 'C:\path\to\nlp-survey-ch3-d3-b1.txt'
        '64k'  = 'C:\path\to\nlp-survey-ch3-d7-b1.txt'
        '96k'  = 'C:\path\to\nlp-survey-ch3-d11-b1.txt'
        '128k' = 'C:\path\to\nlp-survey-ch3-d15-b1.txt'
        '256k' = 'C:\path\to\nlp-survey-ch3-d31-b1.txt'
    }
}
