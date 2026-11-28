#include "../../../ggml/src/ggml-cuda/convert.cuh"
#include "../../../ggml/rocmfp4/rocmfp4.h"
#include "ggml-alloc.h"
#include "ggml-cuda.h"

#include <algorithm>
#include <cstring>
#include <vector>

extern thread_local int rocmfp4_test_sgemms;

namespace {
enum operation { F32_C, F32_NC, F16_C, F16_NC, MM, MM_ID };
struct test_case {
    const char * id;
    const char * op_name;
    operation op;
    int k, m, e, t, s, b, padding, gap, offset, pitch, expected_sgemms;
};
constexpr test_case cases[] = {
#define CASE(id, op, ...) {id, #op, op, __VA_ARGS__},
#include "cases.inc"
#undef CASE
};

void convert(const test_case & c, const uint8_t * packed, size_t bytes, uint8_t * result, size_t count) {
    const bool half_output = c.op == F16_C || c.op == F16_NC;
    const int row = c.k / 32 + c.padding;
    const size_t payload = count * (half_output ? 2 : 4);
    std::vector<uint8_t> checked(payload + 64, 0xa5);
    uint8_t * input;
    uint8_t * output;
    CUDA_CHECK(hipMalloc(&input, bytes));
    CUDA_CHECK(hipMalloc(&output, checked.size()));
    CUDA_CHECK(hipMemcpy(input, packed, bytes, hipMemcpyHostToDevice));
    CUDA_CHECK(hipMemcpy(output, checked.data(), checked.size(), hipMemcpyHostToDevice));
    const void * blocks = input + 17*c.offset;
    const auto type = GGML_TYPE_ROCMFP4_FAST;
    switch (c.op) {
        case F32_C:  ggml_get_to_fp32_cuda(type)(blocks, (float *)(output + 32), count, nullptr); break;
        case F16_C:  ggml_get_to_fp16_cuda(type)(blocks, (half *)(output + 32), count, nullptr); break;
        case F32_NC: ggml_get_to_fp32_nc_cuda(type)(blocks, (float *)(output + 32), c.k, c.m, 1, 1, row, row*c.m, row*c.m, nullptr); break;
        case F16_NC: ggml_get_to_fp16_nc_cuda(type)(blocks, (half *)(output + 32), c.k, c.m, 1, 1, row, row*c.m, row*c.m, nullptr); break;
        default: GGML_ABORT("invalid converter");
    }
    CUDA_CHECK(hipGetLastError());
    CUDA_CHECK(hipMemcpy(checked.data(), output, checked.size(), hipMemcpyDeviceToHost));
    for (size_t i = 0; i < 32; ++i) {
        GGML_ASSERT(checked[i] == 0xa5 && checked[32 + payload + i] == 0xa5);
    }
    std::memcpy(result, checked.data() + 32, payload);
    std::vector<uint8_t> copy(bytes);
    CUDA_CHECK(hipMemcpy(copy.data(), input, bytes, hipMemcpyDeviceToHost));
    GGML_ASSERT(std::memcmp(copy.data(), packed, bytes) == 0);
    std::vector<float> reference(c.k);
    for (int r = 0; r < c.m; ++r) {
        rocmfp4_dequantize_row_q4_0_fast((const block_rocmfp4_fast *)(packed + 17*(c.offset + r*row)), reference.data(), c.k);
        for (int j = 0; j < c.k; ++j) {
            const size_t index = size_t(r)*c.k + j;
            if (half_output) {
                const ggml_fp16_t bits = ggml_fp32_to_fp16(reference[j]);
                GGML_ASSERT(std::memcmp(result + 2*index, &bits, 2) == 0);
            } else {
                GGML_ASSERT(std::memcmp(result + 4*index, &reference[j], 4) == 0);
            }
        }
    }
    CUDA_CHECK(hipFree(output));
    CUDA_CHECK(hipFree(input));
}

void multiply(const test_case & c, const uint8_t * packed, size_t bytes, const float * x,
              const int32_t * indices, uint8_t * result) {
    auto backend = ggml_backend_cuda_init(0);
    GGML_ASSERT(backend && std::strcmp(ggml_backend_name(backend), "ROCm0") == 0);
    auto ctx = ggml_init({2*1024*1024, nullptr, true});
    auto root = ggml_new_tensor_1d(ctx, GGML_TYPE_ROCMFP4_FAST, bytes/17*32);
    const int row = 17*(c.k/32 + c.padding);
    const int expert = row*c.m + 17*c.gap;
    auto w = ggml_view_3d(ctx, root, c.k, c.m, c.e, row, expert, c.offset*17);
    auto activation = ggml_new_tensor_3d(ctx, GGML_TYPE_F32, c.k, c.b, c.t);
    ggml_tensor * parent = nullptr;
    ggml_tensor * ids = nullptr;
    ggml_tensor * dst;
    if (c.op == MM_ID) {
        parent = ggml_new_tensor_2d(ctx, GGML_TYPE_I32, c.pitch, c.t);
        ids = ggml_view_2d(ctx, parent, c.s, c.t, c.pitch*4, 0);
        dst = ggml_mul_mat_id(ctx, w, activation, ids);
    } else {
        dst = ggml_mul_mat(ctx, w, activation);
    }
    auto dev = ggml_backend_get_device(backend);
    GGML_ASSERT(ggml_backend_dev_supports_op(dev, dst));
    // Probe the actual predicate without launching an operation.
    ggml_tensor candidate = *dst;
    ggml_tensor weight = *w;
    candidate.src[0] = &weight;
    for (const int k : {31, 159, INT32_MAX}) {
        weight.ne[0] = k;
        GGML_ASSERT(!ggml_backend_dev_supports_op(dev, &candidate));
    }
    weight = *w;
    weight.nb[0] = 18;
    GGML_ASSERT(!ggml_backend_dev_supports_op(dev, &candidate));
    weight = *w;
    ++weight.nb[1];
    GGML_ASSERT(!ggml_backend_dev_supports_op(dev, &candidate));
    weight = *w;
    weight.view_offs = bytes;
    GGML_ASSERT(!ggml_backend_dev_supports_op(dev, &candidate));
    weight = *w;
    candidate.type = GGML_TYPE_F16;
    GGML_ASSERT(!ggml_backend_dev_supports_op(dev, &candidate));
    if (ids) {
        candidate = *dst;
        ggml_tensor index = *ids;
        candidate.src[2] = &index;
        index.type = GGML_TYPE_I64;
        GGML_ASSERT(!ggml_backend_dev_supports_op(dev, &candidate));
        index = *ids;
        index.nb[1] = 4*c.s - 1;
        GGML_ASSERT(!ggml_backend_dev_supports_op(dev, &candidate));
        index.nb[1] = SIZE_MAX - 3;
        GGML_ASSERT(!ggml_backend_dev_supports_op(dev, &candidate));
    }
    if (ids && c.e > 1) {
        candidate = *dst;
        candidate.src[0] = &weight;
        weight = *w;
        weight.nb[2] = 17;
        GGML_ASSERT(!ggml_backend_dev_supports_op(dev, &candidate));
        weight.nb[2] = bytes;
        GGML_ASSERT(!ggml_backend_dev_supports_op(dev, &candidate));
        ggml_tensor narrow = *ids;
        narrow.ne[0] += 1;
        candidate = *dst;
        candidate.src[2] = &narrow;
        GGML_ASSERT(!ggml_backend_dev_supports_op(dev, &candidate));
    }
    candidate = *dst;
    candidate.nb[1] += 4;
    GGML_ASSERT(!ggml_backend_dev_supports_op(dev, &candidate));
    candidate = *dst;
    candidate.op_params[0] = GGML_PREC_F16;
    GGML_ASSERT(!ggml_backend_dev_supports_op(dev, &candidate));
    candidate = *dst;
    candidate.op_params[3] = GGML_PREC_F32;
    GGML_ASSERT(!ggml_backend_dev_supports_op(dev, &candidate));
    for (auto buft : {ggml_backend_cuda_buffer_type(0), ggml_backend_cpu_buffer_type(), ggml_backend_cuda_host_buffer_type()}) {
        root->buffer = ggml_backend_buft_alloc_buffer(buft, 0);
        GGML_ASSERT(ggml_backend_dev_supports_op(dev, dst) == (buft == ggml_backend_cuda_buffer_type(0)));
        ggml_backend_buffer_free(root->buffer);
        root->buffer = nullptr;
    }
    auto buffer = ggml_backend_alloc_ctx_tensors(ctx, backend);
    GGML_ASSERT(buffer && ggml_backend_dev_supports_op(dev, dst));
    ggml_backend_buffer_set_usage(buffer, GGML_BACKEND_BUFFER_USAGE_COMPUTE);
    GGML_ASSERT(!ggml_backend_dev_supports_op(dev, dst));
    ggml_backend_buffer_set_usage(buffer, GGML_BACKEND_BUFFER_USAGE_WEIGHTS);
    ggml_backend_tensor_set(root, packed, 0, bytes);
    ggml_backend_tensor_set(activation, x, 0, ggml_nbytes(activation));
    if (parent) {
        ggml_backend_tensor_set(parent, indices, 0, ggml_nbytes(parent));
    }
    ggml_backend_tensor_memset(dst, 0xa5, 0, ggml_nbytes(dst));
    auto graph = ggml_new_graph_custom(ctx, 16, false);
    ggml_build_forward_expand(graph, dst);
    GGML_ASSERT(ggml_graph_n_nodes(graph) == (ids ? 3 : 2));
    for (int i = 0; i < ggml_graph_n_nodes(graph); ++i) {
        auto node = ggml_graph_node(graph, i);
        GGML_ASSERT(node == dst || node == w || node == ids);
    }
    GGML_ASSERT(ggml_graph_node(graph, -1) == dst && dst->ne[0] == c.m && dst->ne[1] == c.s &&
                dst->ne[2] == c.t && dst->ne[3] == 1 && ggml_backend_dev_supports_op(dev, dst));
    GGML_ASSERT(ggml_backend_graph_compute(backend, graph) == GGML_STATUS_SUCCESS);
    ggml_backend_synchronize(backend);
    GGML_ASSERT(rocmfp4_test_sgemms == c.expected_sgemms);
    ggml_backend_tensor_get(dst, result, 0, ggml_nbytes(dst));
    ggml_backend_buffer_free(buffer);
    ggml_free(ctx);
    ggml_backend_free(backend);
}
} // namespace

extern "C" __declspec(dllexport) int evox2_hip2a_case(const char * id, const char * op_name, const int * geometry,
        const uint8_t * packed, size_t bytes,
        const float * x, size_t nx, const int32_t * indices, size_t ni, uint8_t * result, size_t result_bytes) {
    GGML_ASSERT(id && op_name && geometry);
    for (const auto & c : cases) {
        if (std::strcmp(c.id, id) != 0) {
            continue;
        }
        const int expected[] = {c.k, c.m, c.e, c.t, c.s, c.b, c.padding, c.gap, c.offset, c.pitch};
        GGML_ASSERT(std::strcmp(c.op_name, op_name) == 0 && std::equal(expected, expected + 10, geometry));
        const bool gemm = c.op == MM || c.op == MM_ID;
        const size_t count = gemm ? c.m*c.s*c.t : c.m*c.k;
        GGML_ASSERT(bytes == 17u*(c.offset + c.e*((c.k/32 + c.padding)*c.m + c.gap) + 1));
        GGML_ASSERT(result_bytes == count*(c.op == F16_C || c.op == F16_NC ? 2 : 4));
        GGML_ASSERT(nx == size_t(gemm ? c.k*c.b*c.t : 0) && ni == size_t(c.pitch*c.t));
        GGML_ASSERT(packed && result && (!nx || x) && (!ni || indices));
        int sgemms = gemm ? 1 : 0;
        if (c.op == MM_ID) {
            constexpr int ids7[] = {3, 1};
            constexpr int ids8[] = {2, 0, 0, 2, 2, 2};
            constexpr int ids9[] = {2, 0, 1, 2, 1, -1, 2, 0, 0, 2};
            const int * active = std::strcmp(id, "7") == 0 ? ids7 : std::strcmp(id, "8") == 0 ? ids8 : ids9;
            const bool all_skipped = std::strcmp(id, "9-Z") == 0;
            std::vector<bool> used(c.e, false);
            for (int t = 0; t < c.t; ++t) {
                for (int slot = 0; slot < c.s; ++slot) {
                    const int expert = indices[t*c.pitch + slot];
                    GGML_ASSERT(expert >= -1 && expert < c.e);
                    GGML_ASSERT(expert == (all_skipped ? -1 : active[t*c.s + slot]));
                    if (expert >= 0) {
                        used[expert] = true;
                    }
                }
            }
            sgemms = int(std::count(used.begin(), used.end(), true));
        }
        GGML_ASSERT(sgemms == c.expected_sgemms && rocmfp4_test_sgemms == 0);
        GGML_ASSERT(ggml_hip_rocmfp4_fast_device(0));
        CUDA_CHECK(hipSetDevice(0));
        if (gemm) {
            multiply(c, packed, bytes, x, indices, result);
        } else {
            convert(c, packed, bytes, result, count);
        }
        return 1;
    }
    return 0;
}
