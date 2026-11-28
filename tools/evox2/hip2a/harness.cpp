#include "../../../ggml/src/ggml-cuda/convert.cuh"
#include "../../../ggml/rocmfp4/rocmfp4.h"
#include "ggml-alloc.h"
#include "ggml-cuda.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <vector>

extern thread_local int rocmfp4_test_sgemms;

extern thread_local int rocmfp4_test_h2d, rocmfp4_test_d2h, rocmfp4_test_host_reads;
extern thread_local size_t rocmfp4_test_id_span, rocmfp4_test_id_pitch;

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
    const auto type = GGML_TYPE_Q4_0_ROCMFP4_FAST;
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

bool same_layout(const ggml_tensor * a, const ggml_tensor * b) {
    return a->type == b->type && std::equal(a->ne, a->ne + GGML_MAX_DIMS, b->ne) &&
           std::equal(a->nb, a->nb + GGML_MAX_DIMS, b->nb);
}

void expect_bytes(ggml_tensor * tensor, const void * expected, size_t n) {
    GGML_ASSERT(ggml_nbytes(tensor) == n);
    std::vector<uint8_t> actual(n);
    ggml_backend_tensor_get(tensor, actual.data(), 0, n);
    GGML_ASSERT(std::memcmp(actual.data(), expected, n) == 0);
}

void schedule(const test_case & c, ggml_backend_reg_t cpu_reg, ggml_backend_t hip, ggml_context * ctx,
              ggml_tensor * root, ggml_tensor * w, ggml_tensor * activation, ggml_tensor * parent,
              ggml_tensor * ids, ggml_tensor * dst, const uint8_t * packed, size_t bytes,
              const float * x, const int32_t * indices, uint8_t * result) {
    GGML_ASSERT(ggml_backend_reg_dev_count(cpu_reg) == 1);
    auto cpu_dev = ggml_backend_reg_dev_get(cpu_reg, 0);
    GGML_ASSERT(ggml_backend_dev_type(cpu_dev) == GGML_BACKEND_DEVICE_TYPE_CPU);
    auto cpu = ggml_backend_dev_init(cpu_dev, nullptr);
    GGML_ASSERT(cpu);
    ggml_backend_t backends[] = {hip, cpu};
    auto sched = ggml_backend_sched_new(backends, nullptr, 2, 64, false, false);
    GGML_ASSERT(sched);
    const bool cpu_input = std::strcmp(c.id, "S-HC-CPU") == 0;
    const bool split_copy = cpu_input || std::strcmp(c.id, "S-HC-PIN-COPY") == 0;
    const bool pinned_io = std::strcmp(c.id, "S-HC-PIN-REJECT") == 0;
    const auto device = ggml_backend_cuda_buffer_type(0);
    const auto host = ggml_backend_cuda_host_buffer_type();
    const auto input_type = cpu_input ? ggml_backend_cpu_buffer_type() : ids ? device : host;
    std::vector<ggml_tensor *> owned;
    auto allocate = [&](ggml_tensor * t, ggml_backend_buffer_type_t type) {
        const size_t guard = ggml_backend_buft_get_alignment(type);
        auto buf = ggml_backend_buft_alloc_buffer(type, guard + ggml_backend_buft_get_alloc_size(type, t) + guard);
        GGML_ASSERT(buf && ggml_backend_buffer_get_type(buf) == type);
        ggml_backend_buffer_clear(buf, 0xa5);
        auto base = static_cast<uint8_t *>(ggml_backend_buffer_get_base(buf));
        GGML_ASSERT(ggml_backend_tensor_alloc(buf, t, base + guard) == GGML_STATUS_SUCCESS);
        owned.push_back(t);
    };
    allocate(root, device);
    ggml_backend_buffer_set_usage(root->buffer, GGML_BACKEND_BUFFER_USAGE_WEIGHTS);
    GGML_ASSERT(ggml_backend_view_init(w) == GGML_STATUS_SUCCESS);
    allocate(activation, input_type);
    ggml_set_input(activation);
    if (ids) {
        allocate(parent, host);
        GGML_ASSERT(ggml_backend_view_init(ids) == GGML_STATUS_SUCCESS);
        ggml_backend_tensor_set(parent, indices, 0, ggml_nbytes(parent));
    }
    if (pinned_io) {
        allocate(dst, host);
    }
    ggml_backend_tensor_set(root, packed, 0, bytes);
    ggml_backend_tensor_set(activation, x, 0, ggml_nbytes(activation));
    auto graph = ggml_new_graph_custom(ctx, 16, false);
    ggml_build_forward_expand(graph, dst);
    auto cleanup = [&]() {
        ggml_backend_sched_free(sched);
        for (auto t : owned) {
            ggml_backend_buffer_free(t->buffer);
        }
        ggml_backend_free(cpu);
    };
    if (pinned_io) {
        const bool hb = ggml_backend_supports_buft(hip, host);
        const bool ho = ggml_backend_supports_op(hip, dst);
        const bool cb = ggml_backend_supports_buft(cpu, host);
        const bool co = ggml_backend_supports_op(cpu, dst);
        std::fprintf(stderr, "placement probe %s hip_buft=%d hip_op=%d cpu_buft=%d cpu_op=%d\n",
                     c.id, hb, ho, cb, co);
        const bool allocated = ggml_backend_sched_alloc_graph(sched, graph);
        auto assigned = allocated ? ggml_backend_sched_get_tensor_backend(sched, dst) : nullptr;
        std::fprintf(stderr, "%s backend=%s weight=%s activation=%s dst=%s hip_buft=%d hip_op=%d "
                     "cpu_buft=%d cpu_op=%d alloc=%d split_copy=%d id_copy=0 observed_span=0 observed_pitch=0 compute=0 ops=0 sgemms=%d stage_h2d=%d "
                     "stage_d2h=%d host_reads=%d span=%zu pitch=%zu\n", c.id,
                     assigned ? ggml_backend_name(assigned) : "-",
                     ggml_backend_buffer_name(w->buffer), ggml_backend_buffer_name(activation->buffer),
                     ggml_backend_buffer_name(dst->buffer), hb, ho, cb, co, allocated, int(dst->src[1] != activation), rocmfp4_test_sgemms,
                     rocmfp4_test_h2d, rocmfp4_test_d2h, rocmfp4_test_host_reads,
                     rocmfp4_test_id_span, rocmfp4_test_id_pitch);
        GGML_ASSERT(!hb && !ho && cb && co && allocated && assigned == cpu && dst->src[1] == activation);
        GGML_ASSERT(!rocmfp4_test_sgemms && !rocmfp4_test_h2d && !rocmfp4_test_d2h &&
                    !rocmfp4_test_host_reads && !rocmfp4_test_id_span && !rocmfp4_test_id_pitch);
        cleanup();
        return;
    }
    GGML_ASSERT(ggml_backend_sched_alloc_graph(sched, graph));
    GGML_ASSERT(ggml_backend_sched_get_tensor_backend(sched, dst) == hip);
    GGML_ASSERT(ggml_graph_n_nodes(graph) == (ids ? 3 : 2));
    for (int i = 0; i < ggml_graph_n_nodes(graph); ++i) {
        auto node = ggml_graph_node(graph, i);
        GGML_ASSERT(node == dst || ((node == w || node == ids) && node->op == GGML_OP_VIEW));
    }
    GGML_ASSERT(dst->op == (ids ? GGML_OP_MUL_MAT_ID : GGML_OP_MUL_MAT));
    GGML_ASSERT(dst->ne[0] == c.m && dst->ne[1] == c.s && dst->ne[2] == c.t && dst->ne[3] == 1);
    GGML_ASSERT(dst->src[0] == w && w->view_src == root && w->src[0] == root && w->buffer == root->buffer &&
                w->data == static_cast<uint8_t *>(root->data) + 17*c.offset);
    auto actual_x = dst->src[1];
    auto type_of = [](ggml_tensor * t) { return ggml_backend_buffer_get_type(t->buffer); };
    GGML_ASSERT(!activation->view_src && !actual_x->view_src && !dst->view_src);
    GGML_ASSERT(type_of(w) == device && type_of(activation) == input_type);
    GGML_ASSERT(type_of(actual_x) == (split_copy ? device : input_type));
    GGML_ASSERT(type_of(dst) == device);
    GGML_ASSERT(split_copy == (actual_x != activation) && split_copy == (actual_x->data != activation->data));
    if (split_copy) {
        GGML_ASSERT(same_layout(actual_x, activation));
        GGML_ASSERT(ggml_backend_sched_get_tensor_backend(sched, activation) == cpu);
        GGML_ASSERT(ggml_nbytes(actual_x) == ggml_nbytes(activation));
        ggml_backend_tensor_memset(actual_x, 0xff, 0, ggml_nbytes(actual_x));
    }
    auto actual_ids = dst->src[2];
    if (ids) {
        GGML_ASSERT(actual_ids && actual_ids != ids && actual_ids->data != ids->data && !actual_ids->view_src &&
                    actual_ids->view_offs == 0 && type_of(actual_ids) == device &&
                    same_layout(actual_ids, ids) && ggml_nbytes(parent) == 6144);
        ggml_backend_tensor_memset(actual_ids, 0xff, 0, ggml_nbytes(actual_ids));
        GGML_ASSERT(ids->view_src == parent && ids->src[0] == parent && ids->view_offs == 0 &&
                    ids->buffer == parent->buffer && ids->data == parent->data && type_of(ids) == host &&
                    ids->nb[0] == 4 && ids->nb[1] == 4u*c.pitch && ggml_nbytes(ids) == 4104);
    }
    ggml_backend_tensor_memset(dst, 0xff, 0, ggml_nbytes(dst));
    struct observation {
        ggml_tensor * dst;
        const float * x;
        ggml_tensor * activation;
        ggml_tensor * ids;
        size_t bytes;
        const int32_t * indices;
        int completed;
    } seen{dst, x, activation, ids, ggml_nbytes(activation), ids ? indices : nullptr, 0};
    ggml_backend_sched_set_eval_callback(sched, [](ggml_tensor * node, bool ask, void * user) {
        auto & obs = *static_cast<observation *>(user);
        if (node != obs.dst) {
            GGML_ASSERT(node->op == GGML_OP_VIEW);
            return false;
        }
        if (ask) {
            // Split inputs have been copied. Check every byte before the operation consumes it.
            GGML_ASSERT(same_layout(node->src[1], obs.activation));
            expect_bytes(node->src[1], obs.x, obs.bytes);
            if (obs.indices) {
                GGML_ASSERT(same_layout(node->src[2], obs.ids));
                expect_bytes(node->src[2], obs.indices, 4104);
            }
        } else {
            ++obs.completed;
        }
        return true;
    }, &seen);
    GGML_ASSERT(ggml_backend_sched_graph_compute(sched, graph) == GGML_STATUS_SUCCESS);
    GGML_ASSERT(seen.completed == 1 && rocmfp4_test_sgemms == c.expected_sgemms);
    GGML_ASSERT(!rocmfp4_test_h2d && !rocmfp4_test_d2h && !rocmfp4_test_host_reads &&
                !rocmfp4_test_id_span && !rocmfp4_test_id_pitch);
    expect_bytes(root, packed, bytes);
    expect_bytes(activation, x, ggml_nbytes(activation));
    if (parent) {
        expect_bytes(parent, indices, ggml_nbytes(parent));
    }
    for (auto t : owned) {
        auto type = type_of(t);
        const size_t guard = ggml_backend_buft_get_alignment(type);
        const auto data = static_cast<const uint8_t *>(t->data);
        std::vector<uint8_t> check(guard);
        for (const auto addr : {data - guard, data + ggml_backend_buft_get_alloc_size(type, t)}) {
            if (type == device) {
                CUDA_CHECK(hipMemcpy(check.data(), addr, guard, hipMemcpyDeviceToHost));
            } else {
                std::memcpy(check.data(), addr, guard);
            }
            GGML_ASSERT(std::all_of(check.begin(), check.end(), [](uint8_t v) { return v == 0xa5; }));
        }
    }
    ggml_backend_tensor_get(dst, result, 0, ggml_nbytes(dst));
    std::fprintf(stderr, "%s backend=%s weight=%s activation=%s->%s dst=%s ids=%s split_copy=%d id_copy=%d observed_span=%zu observed_pitch=%zu "
                 "stage_h2d=%d stage_d2h=%d host_reads=%d span=%zu pitch=%zu ops=%d sgemms=%d\n",
                 c.id, ggml_backend_name(ggml_backend_sched_get_tensor_backend(sched, dst)), ggml_backend_buft_name(type_of(w)), ggml_backend_buft_name(input_type),
                 ggml_backend_buft_name(type_of(actual_x)), ggml_backend_buft_name(type_of(dst)),
                 ids ? ggml_backend_buft_name(type_of(actual_ids)) : "-", int(actual_x != activation),
                 int(ids && actual_ids != ids), actual_ids ? ggml_nbytes(actual_ids) : size_t(0),
                 actual_ids ? actual_ids->nb[1] : size_t(0), rocmfp4_test_h2d,
                 rocmfp4_test_d2h, rocmfp4_test_host_reads, rocmfp4_test_id_span, rocmfp4_test_id_pitch,
                 seen.completed, rocmfp4_test_sgemms);
    cleanup();
}

void multiply(ggml_backend_reg_t cpu_reg, const test_case & c, const uint8_t * packed, size_t bytes, const float * x,
              const int32_t * indices, uint8_t * result) {
    auto backend = ggml_backend_cuda_init(0);
    GGML_ASSERT(backend && std::strcmp(ggml_backend_name(backend), "ROCm0") == 0);
    auto ctx = ggml_init({2*1024*1024, nullptr, true});
    auto root = ggml_new_tensor_1d(ctx, GGML_TYPE_Q4_0_ROCMFP4_FAST, bytes/17*32);
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
    if (cpu_reg) {
        schedule(c, cpu_reg, backend, ctx, root, w, activation, parent, ids, dst, packed, bytes, x, indices, result);
        ggml_free(ctx);
        ggml_backend_free(backend);
        return;
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

int run_case(ggml_backend_reg_t cpu_reg, const char * id, const char * op_name, const int * geometry,
        const uint8_t * packed, size_t bytes,
        const float * x, size_t nx, const int32_t * indices, size_t ni, uint8_t * result, size_t result_bytes) {
    GGML_ASSERT(id && op_name && geometry);
    for (const auto & c : cases) {
        if ((cpu_reg != nullptr) != (c.id[0] == 'S') || std::strcmp(c.id, id) != 0) {
            continue;
        }
        const int expected[] = {c.k, c.m, c.e, c.t, c.s, c.b, c.padding, c.gap, c.offset, c.pitch};
        GGML_ASSERT(std::strcmp(c.op_name, op_name) == 0 && std::equal(expected, expected + 10, geometry));
        const bool gemm = c.op == MM || c.op == MM_ID;
        const size_t count = gemm ? c.m*c.s*c.t : c.m*c.k;
        GGML_ASSERT(bytes == 17u*(c.offset + c.e*((c.k/32 + c.padding)*c.m + c.gap) + 1));
        const bool placement = std::strcmp(id, "S-HC-PIN-REJECT") == 0;
        GGML_ASSERT(result_bytes == (placement ? 0 : count*(c.op == F16_C || c.op == F16_NC ? 2 : 4)));
        GGML_ASSERT(nx == size_t(gemm ? c.k*c.b*c.t : 0) && ni == size_t(c.pitch*c.t));
        GGML_ASSERT(packed && (placement ? !result : result != nullptr) && (!nx || x) && (!ni || indices));
        int sgemms = gemm && !placement ? 1 : 0;
        if (c.op == MM_ID) {
            constexpr int ids7[] = {3, 1};
            constexpr int ids8[] = {2, 0, 0, 2, 2, 2};
            constexpr int ids9[] = {2, 0, 1, 2, 1, -1, 2, 0, 0, 2};
            const int * active = std::strcmp(id, "7") == 0 ? ids7 : (std::strcmp(id, "8") == 0 || cpu_reg) ? ids8 : ids9;
            const bool all_skipped = std::strcmp(id, "9-Z") == 0;
            std::vector<bool> used(c.e, false);
            for (int t = 0; t < c.t; ++t) {
                if (cpu_reg) {
                    for (int j = c.s; j < c.pitch; ++j) {
                        GGML_ASSERT(indices[t*c.pitch + j] == -99);
                    }
                }
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
            multiply(cpu_reg, c, packed, bytes, x, indices, result);
        } else {
            convert(c, packed, bytes, result, count);
        }
        return 1;
    }
    return 0;
}
} // namespace

extern "C" __declspec(dllexport) int evox2_hip2a_case(const char * id, const char * op_name, const int * geometry,
        const uint8_t * packed, size_t bytes,
        const float * x, size_t nx, const int32_t * indices, size_t ni, uint8_t * result, size_t result_bytes) {
    return run_case(nullptr, id, op_name, geometry, packed, bytes, x, nx, indices, ni, result, result_bytes);
}

extern "C" __declspec(dllexport) int evox2_hip2e_sched_case(ggml_backend_reg_t cpu_reg, const char * id, const char * op_name, const int * geometry,
        const uint8_t * packed, size_t bytes,
        const float * x, size_t nx, const int32_t * indices, size_t ni, uint8_t * result, size_t result_bytes) {
    GGML_ASSERT(cpu_reg);
    return run_case(cpu_reg, id, op_name, geometry, packed, bytes, x, nx, indices, ni, result, result_bytes);
}
