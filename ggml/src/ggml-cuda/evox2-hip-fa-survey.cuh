#pragma once

#if defined(GGML_USE_HIP)
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace evox2_hip_fa_survey {

static constexpr int64_t kv_band_tokens = 4096;
static constexpr int max_kv_band = 64;
static constexpr int layer_grid_base = 129;
static constexpr int unknown_layer_blocks = 128;

template <int band>
static __global__ void evox2_hip_fa_survey_kv_band() {
#if defined(__HIP_PLATFORM_AMD__)
#pragma unroll
    for (int i = 0; i <= band; ++i) {
        asm volatile("s_nop 0");
    }
#endif
}

static __global__ void evox2_hip_fa_survey_kv_overflow() {
#if defined(__HIP_PLATFORM_AMD__)
    asm volatile("s_nop 0");
#endif
}

static bool enabled() {
    static const bool value = [] {
        const char * const env = std::getenv("GGML_HIP_RGP_FA_SURVEY");
        return env != nullptr && std::strcmp(env, "1") == 0;
    }();
    return value;
}

static void submit(int64_t kv, int64_t n, long layer, cudaStream_t stream) {
    if (kv < 0) {
        return;
    }

    const int64_t band_index = kv / kv_band_tokens;
    const int band = band_index <= max_kv_band ? (int) band_index : -1;
    const int blocks = layer >= 0 && layer <= 126 ? layer_grid_base + (int) layer : unknown_layer_blocks;

    switch (band) {

        case 0: evox2_hip_fa_survey_kv_band<0><<<blocks, 64, 0, stream>>>(); break;
        case 1: evox2_hip_fa_survey_kv_band<1><<<blocks, 64, 0, stream>>>(); break;
        case 2: evox2_hip_fa_survey_kv_band<2><<<blocks, 64, 0, stream>>>(); break;
        case 3: evox2_hip_fa_survey_kv_band<3><<<blocks, 64, 0, stream>>>(); break;
        case 4: evox2_hip_fa_survey_kv_band<4><<<blocks, 64, 0, stream>>>(); break;
        case 5: evox2_hip_fa_survey_kv_band<5><<<blocks, 64, 0, stream>>>(); break;
        case 6: evox2_hip_fa_survey_kv_band<6><<<blocks, 64, 0, stream>>>(); break;
        case 7: evox2_hip_fa_survey_kv_band<7><<<blocks, 64, 0, stream>>>(); break;
        case 8: evox2_hip_fa_survey_kv_band<8><<<blocks, 64, 0, stream>>>(); break;
        case 9: evox2_hip_fa_survey_kv_band<9><<<blocks, 64, 0, stream>>>(); break;
        case 10: evox2_hip_fa_survey_kv_band<10><<<blocks, 64, 0, stream>>>(); break;
        case 11: evox2_hip_fa_survey_kv_band<11><<<blocks, 64, 0, stream>>>(); break;
        case 12: evox2_hip_fa_survey_kv_band<12><<<blocks, 64, 0, stream>>>(); break;
        case 13: evox2_hip_fa_survey_kv_band<13><<<blocks, 64, 0, stream>>>(); break;
        case 14: evox2_hip_fa_survey_kv_band<14><<<blocks, 64, 0, stream>>>(); break;
        case 15: evox2_hip_fa_survey_kv_band<15><<<blocks, 64, 0, stream>>>(); break;
        case 16: evox2_hip_fa_survey_kv_band<16><<<blocks, 64, 0, stream>>>(); break;
        case 17: evox2_hip_fa_survey_kv_band<17><<<blocks, 64, 0, stream>>>(); break;
        case 18: evox2_hip_fa_survey_kv_band<18><<<blocks, 64, 0, stream>>>(); break;
        case 19: evox2_hip_fa_survey_kv_band<19><<<blocks, 64, 0, stream>>>(); break;
        case 20: evox2_hip_fa_survey_kv_band<20><<<blocks, 64, 0, stream>>>(); break;
        case 21: evox2_hip_fa_survey_kv_band<21><<<blocks, 64, 0, stream>>>(); break;
        case 22: evox2_hip_fa_survey_kv_band<22><<<blocks, 64, 0, stream>>>(); break;
        case 23: evox2_hip_fa_survey_kv_band<23><<<blocks, 64, 0, stream>>>(); break;
        case 24: evox2_hip_fa_survey_kv_band<24><<<blocks, 64, 0, stream>>>(); break;
        case 25: evox2_hip_fa_survey_kv_band<25><<<blocks, 64, 0, stream>>>(); break;
        case 26: evox2_hip_fa_survey_kv_band<26><<<blocks, 64, 0, stream>>>(); break;
        case 27: evox2_hip_fa_survey_kv_band<27><<<blocks, 64, 0, stream>>>(); break;
        case 28: evox2_hip_fa_survey_kv_band<28><<<blocks, 64, 0, stream>>>(); break;
        case 29: evox2_hip_fa_survey_kv_band<29><<<blocks, 64, 0, stream>>>(); break;
        case 30: evox2_hip_fa_survey_kv_band<30><<<blocks, 64, 0, stream>>>(); break;
        case 31: evox2_hip_fa_survey_kv_band<31><<<blocks, 64, 0, stream>>>(); break;
        case 32: evox2_hip_fa_survey_kv_band<32><<<blocks, 64, 0, stream>>>(); break;
        case 33: evox2_hip_fa_survey_kv_band<33><<<blocks, 64, 0, stream>>>(); break;
        case 34: evox2_hip_fa_survey_kv_band<34><<<blocks, 64, 0, stream>>>(); break;
        case 35: evox2_hip_fa_survey_kv_band<35><<<blocks, 64, 0, stream>>>(); break;
        case 36: evox2_hip_fa_survey_kv_band<36><<<blocks, 64, 0, stream>>>(); break;
        case 37: evox2_hip_fa_survey_kv_band<37><<<blocks, 64, 0, stream>>>(); break;
        case 38: evox2_hip_fa_survey_kv_band<38><<<blocks, 64, 0, stream>>>(); break;
        case 39: evox2_hip_fa_survey_kv_band<39><<<blocks, 64, 0, stream>>>(); break;
        case 40: evox2_hip_fa_survey_kv_band<40><<<blocks, 64, 0, stream>>>(); break;
        case 41: evox2_hip_fa_survey_kv_band<41><<<blocks, 64, 0, stream>>>(); break;
        case 42: evox2_hip_fa_survey_kv_band<42><<<blocks, 64, 0, stream>>>(); break;
        case 43: evox2_hip_fa_survey_kv_band<43><<<blocks, 64, 0, stream>>>(); break;
        case 44: evox2_hip_fa_survey_kv_band<44><<<blocks, 64, 0, stream>>>(); break;
        case 45: evox2_hip_fa_survey_kv_band<45><<<blocks, 64, 0, stream>>>(); break;
        case 46: evox2_hip_fa_survey_kv_band<46><<<blocks, 64, 0, stream>>>(); break;
        case 47: evox2_hip_fa_survey_kv_band<47><<<blocks, 64, 0, stream>>>(); break;
        case 48: evox2_hip_fa_survey_kv_band<48><<<blocks, 64, 0, stream>>>(); break;
        case 49: evox2_hip_fa_survey_kv_band<49><<<blocks, 64, 0, stream>>>(); break;
        case 50: evox2_hip_fa_survey_kv_band<50><<<blocks, 64, 0, stream>>>(); break;
        case 51: evox2_hip_fa_survey_kv_band<51><<<blocks, 64, 0, stream>>>(); break;
        case 52: evox2_hip_fa_survey_kv_band<52><<<blocks, 64, 0, stream>>>(); break;
        case 53: evox2_hip_fa_survey_kv_band<53><<<blocks, 64, 0, stream>>>(); break;
        case 54: evox2_hip_fa_survey_kv_band<54><<<blocks, 64, 0, stream>>>(); break;
        case 55: evox2_hip_fa_survey_kv_band<55><<<blocks, 64, 0, stream>>>(); break;
        case 56: evox2_hip_fa_survey_kv_band<56><<<blocks, 64, 0, stream>>>(); break;
        case 57: evox2_hip_fa_survey_kv_band<57><<<blocks, 64, 0, stream>>>(); break;
        case 58: evox2_hip_fa_survey_kv_band<58><<<blocks, 64, 0, stream>>>(); break;
        case 59: evox2_hip_fa_survey_kv_band<59><<<blocks, 64, 0, stream>>>(); break;
        case 60: evox2_hip_fa_survey_kv_band<60><<<blocks, 64, 0, stream>>>(); break;
        case 61: evox2_hip_fa_survey_kv_band<61><<<blocks, 64, 0, stream>>>(); break;
        case 62: evox2_hip_fa_survey_kv_band<62><<<blocks, 64, 0, stream>>>(); break;
        case 63: evox2_hip_fa_survey_kv_band<63><<<blocks, 64, 0, stream>>>(); break;
        case 64: evox2_hip_fa_survey_kv_band<64><<<blocks, 64, 0, stream>>>(); break;
        default: evox2_hip_fa_survey_kv_overflow<<<blocks, 64, 0, stream>>>(); break;
    }
    CUDA_CHECK(cudaGetLastError());

    static std::atomic<int> last_band { -2 };
    if (last_band.exchange(band, std::memory_order_relaxed) != band) {
        std::fprintf(stderr,
                "evox2_hip_fa_survey_v1 band=%d band_tokens=%lld KV=%lld N=%lld layer=%ld grid_blocks=%d"
                " note=host_submission_not_RGP_event\n",
                band, (long long) kv_band_tokens, (long long) kv,
                (long long) n, layer, blocks);
    }
}

} // namespace evox2_hip_fa_survey
#endif // defined(GGML_USE_HIP)
