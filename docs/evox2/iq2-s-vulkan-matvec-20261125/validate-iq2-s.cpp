#include "ggml.h"
#include "ggml-alloc.h"
#include "ggml-backend.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static constexpr int k = 2560;
static constexpr int experts = 512;
static constexpr int slots = 10;

static uint32_t next_u32(uint32_t & state) {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

static bool validate(ggml_backend_t backend, int rows, int tokens, bool indexed, bool skip, bool broadcast) {
    constexpr auto weight_type = GGML_TYPE_IQ2_S;
    const int matrices = indexed ? experts : 1;
    const int b_columns = indexed && !broadcast ? slots : 1;
    const size_t row_size = ggml_row_size(weight_type, k);
    const size_t block_size = ggml_type_size(weight_type);
    const size_t weight_size = row_size * rows * matrices;
    std::vector<uint8_t> weights(weight_size);
    uint32_t rng = 0x1876b4a1;
    for (size_t offset = 0; offset < weight_size; offset += block_size) {
        const ggml_fp16_t delta = ggml_fp32_to_fp16((1 + (next_u32(rng) % 32)) / 8192.0f);
        std::memcpy(weights.data() + offset, &delta, sizeof(delta));
        for (size_t byte = sizeof(delta); byte < block_size; ++byte) {
            weights[offset + byte] = static_cast<uint8_t>(next_u32(rng));
        }
    }
    std::vector<float> b(k * tokens * b_columns);
    for (float & v : b) {
        v = (int(next_u32(rng) % 1025) - 512) / 512.0f;
    }
    std::vector<int32_t> ids(tokens * slots);
    for (int token = 0; token < tokens; ++token) {
        for (int s = 0; s < slots; ++s) {
            ids[token * slots + s] = (511 + token * 19 + s * 37) % experts;
            if (skip && (token == tokens - 1 && tokens > 1 ? true : s % 3 == 0)) {
                ids[token * slots + s] = -1;
            }
        }
    }

    ggml_context * ctx = ggml_init({ggml_tensor_overhead() * 8 + ggml_graph_overhead(), nullptr, true});
    if (!ctx) {
        return false;
    }
    ggml_tensor * a = ggml_new_tensor_3d(ctx, weight_type, k, rows, matrices);
    ggml_tensor * x = indexed ? ggml_new_tensor_3d(ctx, GGML_TYPE_F32, k, b_columns, tokens)
                             : ggml_new_tensor_2d(ctx, GGML_TYPE_F32, k, tokens);
    ggml_tensor * idx = indexed ? ggml_new_tensor_2d(ctx, GGML_TYPE_I32, slots, tokens) : nullptr;
    ggml_tensor * y = indexed ? ggml_mul_mat_id(ctx, a, x, idx) : ggml_mul_mat(ctx, a, x);
    ggml_cgraph * graph = ggml_new_graph(ctx);
    ggml_build_forward_expand(graph, y);
    if (!ggml_backend_supports_op(backend, y)) {
        ggml_free(ctx);
        return false;
    }
    ggml_backend_buffer_t buffer = ggml_backend_alloc_ctx_tensors(ctx, backend);
    if (!buffer) {
        ggml_free(ctx);
        return false;
    }

    std::vector<float> result(ggml_nelements(y), -999.0f);
    ggml_backend_tensor_set(a, weights.data(), 0, weights.size());
    ggml_backend_tensor_set(x, b.data(), 0, b.size() * sizeof(float));
    ggml_backend_tensor_set(y, result.data(), 0, result.size() * sizeof(float));
    if (indexed) {
        ggml_backend_tensor_set(idx, ids.data(), 0, ids.size() * sizeof(int32_t));
    }
    const auto status = ggml_backend_graph_compute(backend, graph);
    if (status != GGML_STATUS_SUCCESS) {
        ggml_backend_buffer_free(buffer);
        ggml_free(ctx);
        return false;
    }
    ggml_backend_tensor_get(y, result.data(), 0, result.size() * sizeof(float));
    ggml_backend_buffer_free(buffer);
    ggml_free(ctx);

    const auto dequantize = ggml_get_type_traits(weight_type)->to_float;
    std::vector<float> decoded(k);
    double squared_error = 0.0;
    double squared_reference = 0.0;
    double max_abs = 0.0;
    int skipped = 0;
    bool pass = true;
    const int used = indexed ? slots : 1;
    for (int token = 0; token < tokens; ++token) {
        for (int s = 0; s < used; ++s) {
            const int expert = indexed ? ids[token * slots + s] : 0;
            skipped += expert < 0;
            const float * v = b.data() + (token * b_columns + s % b_columns) * k;
            for (int row = 0; row < rows; ++row) {
                double reference = 0.0;
                if (expert >= 0) {
                    dequantize(weights.data() + (expert * rows + row) * row_size, decoded.data(), k);
                    for (int j = 0; j < k; ++j) {
                        reference += double(decoded[j]) * v[j];
                    }
                }
                const float actual = result[(token * used + s) * rows + row];
                const double error = std::abs(double(actual) - reference);
                squared_error += error * error;
                squared_reference += reference * reference;
                max_abs = std::max(max_abs, error);
                pass = pass && std::isfinite(actual) &&
                       (expert < 0 ? actual == 0.0f : error <= 2e-5 + 1e-5 * std::abs(reference));
            }
        }
    }
    const double relative_l2 = std::sqrt(squared_error / squared_reference);
    pass = pass && relative_l2 <= 3e-6;
    std::printf("%s,%d,%d,%d,%d,%d,%d,%d,%zu,%.9g,%.9g,%s\n",
                indexed ? "MUL_MAT_ID" : "MUL_MAT", rows, k, matrices, used, tokens, b_columns,
                skipped, result.size(), max_abs, relative_l2, pass ? "PASS" : "FAIL");
    std::fflush(stdout);
    return pass;
}

int main(int argc, char ** argv) {
    if (argc != 2) {
        return 2;
    }
    ggml_backend_reg_t reg = ggml_backend_load(argv[1]);
    if (!reg || ggml_backend_reg_dev_count(reg) != 1) {
        return 3;
    }
    ggml_backend_dev_t dev = ggml_backend_reg_dev_get(reg, 0);
    if (std::strcmp(ggml_backend_dev_name(dev), "Vulkan0") != 0) {
        return 4;
    }
    ggml_backend_t backend = ggml_backend_dev_init(dev, nullptr);
    if (!backend) {
        return 5;
    }
    std::puts("op,m,k,experts,slots,tokens,activation_columns,skipped_slots,outputs,max_abs,relative_l2,result");
    const bool okay = validate(backend, 640, 1, false, false, false) &&
                      validate(backend, 643, 3, false, false, false) &&
                      validate(backend, 643, 8, false, false, false) &&
                      validate(backend, 640, 1, true, false, true) &&
                      validate(backend, 643, 1, true, true, false) &&
                      validate(backend, 643, 3, true, true, false);
    ggml_backend_free(backend);
    return okay ? 0 : 1;
}
