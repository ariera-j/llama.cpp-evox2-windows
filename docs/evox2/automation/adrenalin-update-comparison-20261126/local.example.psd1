@{
    LogRoot = 'C:/REPLACE/logs'
    Builds = @{
        VulkanStage2 = @{ BinDir = 'C:/REPLACE/w43diag/build-ld/bin/Release'; ExpectedBackend = 'Vulkan' }
        Vulkan54 = @{ BinDir = 'C:/REPLACE/w54/build-vk/bin/Release'; ExpectedBackend = 'Vulkan' }
        Rocm54 = @{ BinDir = 'C:/REPLACE/w54/build-rm/bin/Release'; ExpectedBackend = 'ROCm' }
    }
    Models = @{
        UnslothPle16 = @{ Path = 'C:/REPLACE/Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf' }
        AgentionRocmFp4FastPle16 = @{ Path = 'C:/REPLACE/Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf' }
        Gemma31B = @{ Path = 'C:/REPLACE/gemma-4-31B_q4_0-it.gguf' }
    }
    Inputs = @{
        '128k' = 'C:/REPLACE/nlp-survey-ch3-d15-b1.txt'
        '64k' = 'C:/REPLACE/nlp-survey-ch3-d7-b1.txt'
        '32k' = 'C:/REPLACE/nlp-survey-ch3-d3-b1.txt'
    }
}
