@{
    # Copy to ignored local.psd1 and set actual paths for the new worktree.
    # RepoRoot is descriptive; scripts detect their own Git worktree.
    RepoRoot = ''
    LogRoot = ''
    UmaLabel = '96GB'

    Builds = @{
        CleanVulkan = @{
            BinDir = 'C:\path\to\new-worktree\build-vulkan-clean\bin\Release'
            ExpectedBackend = 'Vulkan'
        }
        CleanROCm = @{
            BinDir = 'C:\path\to\new-worktree\build-rocm-clean\bin\Release'
            ExpectedBackend = 'ROCm'
        }
    }

    Models = @{
        # Original joined PLE tensor layout; use the first existing GGUF shard.
        UnslothOriginal = @{
            Path = 'C:\path\to\Qwen3.8-Flash-Next-UD-IQ3_XXS-00001-of-00003.gguf'
            Alias = 'unsloth-original'
        }
    }

    Inputs = @{
        '32k' = 'C:\path\to\nlp-survey-ch3-d3-b1.txt'
        '64k' = 'C:\path\to\nlp-survey-ch3-d7-b1.txt'
        '96k' = 'C:\path\to\nlp-survey-ch3-d11-b1.txt'
        '128k' = 'C:\path\to\nlp-survey-ch3-d15-b1.txt'
        '256k' = 'C:\path\to\nlp-survey-ch3-d31-b1.txt'
    }
}
