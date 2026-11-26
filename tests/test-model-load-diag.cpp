#include "../src/llama-model-load-diag.h"

#include <cassert>
#include <stdexcept>

using namespace llama_load_diag;

static int64_t clock_us = 0;
static unsigned clock_calls = 0;

static int64_t fake_clock() {
    ++clock_calls;
    return clock_us;
}

int main() {
    assert(!enabled(nullptr));
    assert(!enabled(""));
    assert(!enabled("0"));
    assert(!enabled("10"));
    assert(enabled("1"));

    statistics stats;
    stats.record(99, 17);
    for (auto boundary : histogram_limits_us) {
        stats.record(boundary, 1);
    }
    assert(stats.calls == 10 && stats.bytes == 26 && stats.sum_us == 1686199);
    assert(stats.max_us == 1000000 && stats.interval_max_us == 1000000);
    for (auto count : stats.histogram) {
        assert(count == 1);
    }
    const auto limit = std::numeric_limits<uint64_t>::max();
    stats.record(limit, limit);
    assert(stats.sum_us == limit && stats.bytes == limit);
    stats.calls = limit;
    stats.histogram[0] = limit;
    stats.record(0, 1);
    assert(stats.calls == limit && stats.histogram[0] == limit && stats.bytes == limit);

    // Exercise the same null-group fast path used by the loader with the flag off.
    const int result = measure(nullptr, operation::read, [] { return 23; });
    assert(result == 23 && clock_calls == 0);
    if (!enabled(std::getenv("LLAMA_MODEL_LOAD_DIAG"))) {
        return 0;
    }

    const session load{fake_clock, clock_us, stderr};
    {
        group buffer(load, 1, "test\"\\\n");
        const location pos{1, 2, 4100, 4096, 4, 3, 1024};
        buffer.tensor("async_upload", pos);
        measure(&buffer, operation::read, [] { clock_us += 250; }, 1024, pos);
        buffer.complete_tensor();
        // Introductory progress and a reset of the interval maximum.
        clock_us = 4999000;
        measure(&buffer, operation::reuse_wait, [] { clock_us += 2000; }, 0, pos);
        measure(&buffer, operation::reuse_wait, [] { clock_us += 300; }, 0, pos);
        for (int i = 1; i <= 10; ++i) {
            measure(&buffer, operation::upload, [i] { clock_us += 100000 + i; }, 128, pos);
        }
        buffer.finish(true);
    }
    try {
        group buffer(load, 2, "CPU");
        measure(&buffer, operation::host_read, [] {
            clock_us += 120000;
            throw std::runtime_error("simulated failed operation");
        }, 4096);
    } catch (const std::runtime_error &) {
    }
    {
        group buffer(load, 3, "CPU");
        buffer.finish(false);
    }
}
