#pragma once

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <limits>
#include <locale>
#include <sstream>
#include <utility>

namespace llama_load_diag {

inline bool enabled(const char * value) {
    return value && value[0] == '1' && value[1] == '\0';
}

using clock_fn = int64_t (*)();

constexpr uint64_t progress_interval_us = 5000000;
constexpr uint64_t long_wait_us = 100000;
constexpr size_t long_wait_count = 8;
constexpr std::array<uint64_t, 9> histogram_limits_us = {{100, 1000, 5000, 10000, 20000, 50000, 100000, 500000, 1000000}};

enum class operation {
    staging_alloc, event_create, backend_init, seek, read, host_read, first_wait, reuse_wait,
    upload, event_record, sync_set, mapped_set, map_tensor, lock_mapping, drain,
    event_free, staging_free, backend_free, unmap, validation, callback, count
};

constexpr std::array<const char *, size_t(operation::count)> operation_names = {{
    "staging_alloc", "event_create", "backend_init", "seek", "read", "host_read", "first_wait", "reuse_wait",
    "upload", "event_record", "sync_set", "mapped_set", "map_tensor", "lock_mapping", "drain",
    "event_free", "staging_free", "backend_free", "unmap", "validation", "callback",
}};

inline void add(uint64_t & total, uint64_t value) {
    total += std::min(value, std::numeric_limits<uint64_t>::max() - total);
}

struct statistics {
    uint64_t calls = 0;
    uint64_t bytes = 0;
    uint64_t sum_us = 0;
    uint64_t max_us = 0;
    uint64_t interval_max_us = 0;
    std::array<uint64_t, histogram_limits_us.size() + 1> histogram{};

    void record(uint64_t duration, uint64_t size) {
        add(calls, 1);
        add(bytes, size);
        add(sum_us, duration);
        max_us = std::max(max_us, duration);
        interval_max_us = std::max(interval_max_us, duration);
        const auto bin = std::upper_bound(histogram_limits_us.begin(), histogram_limits_us.end(), duration);
        add(histogram[bin - histogram_limits_us.begin()], 1);
    }
};

// Tensor ordinals are one-based in each group and follow the actual load order.
struct location {
    uint64_t tensor = 0;
    int64_t shard = -1;
    uint64_t file_offset = 0;
    uint64_t tensor_file_offset = 0;
    uint64_t tensor_offset = 0;
    int slot = -1;
    uint64_t request_bytes = 0;
};

inline void write_location(std::ostream & out, const location & pos) {
    out << "{\"tensor\":" << pos.tensor << ",\"shard\":" << pos.shard
        << ",\"file_offset\":" << pos.file_offset << ",\"tensor_file_offset\":" << pos.tensor_file_offset
        << ",\"tensor_offset\":" << pos.tensor_offset
        << ",\"slot\":" << pos.slot << ",\"request_bytes\":" << pos.request_bytes << '}';
}

inline void write_string(std::ostream & out, const char * value) {
    out << '"';
    for (size_t i = 0; i < 80 && value[i]; ++i) {
        const unsigned char c = value[i];
        if (c == '"' || c == '\\') {
            out << '\\' << static_cast<char>(c);
        } else if (c < 32 || c >= 127) {
            constexpr char hex[] = "0123456789abcdef";
            out << "\\u00" << hex[c >> 4] << hex[c & 15];
        } else {
            out << static_cast<char>(c);
        }
    }
    out << '"';
}

struct session {
    clock_fn clock;
    int64_t start;
    FILE * output;

    uint64_t elapsed(int64_t now) const {
        return now >= start ? uint64_t(now) - uint64_t(start) : 0;
    }

    template <typename Write>
    void emit(const char * event, int64_t now, Write write) const noexcept {
        try {
            std::ostringstream out;
            out.imbue(std::locale::classic());
            // Start on a new line even when the standard loader prints progress dots.
            out << "\nllama_load_diag {\"schema\":1,\"event\":\"" << event
                << "\",\"load_elapsed_us\":" << elapsed(now);
            write(out);
            out << "}\n";
            const auto line = out.str();
            std::fwrite(line.data(), 1, line.size(), output);
        } catch (...) {
            // Diagnostics must not replace the outcome of the loader.
        }
    }

    void mark(const char * event) const {
        emit(event, clock(), [](std::ostream &) {});
    }
};

struct long_wait {
    uint64_t duration_us = 0;
    uint64_t start_us = 0;
    operation op = operation::read;
    location pos;
};

class group {
public:
    group(const session & load, size_t index, const char * buffer_type)
        : load(load), index(index), buffer_type(buffer_type), started(load.clock()), last_progress(started) {
        report("group_begin", started, false);
    }

    ~group() {
        report("group_end", load.clock(), true);
    }

    group(const group &) = delete;
    group & operator=(const group &) = delete;

    int64_t now() const {
        return load.clock();
    }

    void phase(const char * next) {
        route = next;
        report("group_phase", now(), false);
    }

    void tensor(const char * path, const location & pos) {
        route = path;
        active = pos;
    }

    void complete_tensor() {
        add(completed, 1);
    }

    void finish(bool ok) {
        status = ok ? "ok" : "cancelled";
    }

    void record(operation op, const location & pos, uint64_t bytes, int64_t start, int64_t end) {
        const uint64_t duration = end >= start ? uint64_t(end) - uint64_t(start) : 0;
        operations[size_t(op)].record(duration, bytes);
        if (duration >= long_wait_us) {
            auto least = std::min_element(longest.begin(), longest.end(),
                [](const long_wait & a, const long_wait & b) { return a.duration_us < b.duration_us; });
            if (duration > least->duration_us) {
                *least = {duration, load.elapsed(start), op, pos};
            }
        }
        if (end >= last_progress && uint64_t(end) - uint64_t(last_progress) >= progress_interval_us) {
            report("progress", end, false);
            last_progress = end;
            for (auto & stats : operations) {
                stats.interval_max_us = 0;
            }
        }
    }

private:
    void report(const char * event, int64_t end, bool summary) const {
        load.emit(event, end, [&](std::ostream & out) {
            const uint64_t wall = end >= started ? uint64_t(end) - uint64_t(started) : 0;
            uint64_t classified = 0;
            for (const auto & stats : operations) {
                add(classified, stats.sum_us);
            }
            uint64_t read_bytes = operations[size_t(operation::read)].bytes;
            add(read_bytes, operations[size_t(operation::host_read)].bytes);
            uint64_t transfer_bytes = operations[size_t(operation::upload)].bytes;
            add(transfer_bytes, operations[size_t(operation::sync_set)].bytes);
            add(transfer_bytes, operations[size_t(operation::mapped_set)].bytes);
            out << ",\"group\":" << index << ",\"buffer_type\":";
            write_string(out, buffer_type);
            out << ",\"route\":\"" << route << "\",\"wall_us\":" << wall
                << ",\"classified_us\":" << classified << ",\"unclassified_us\":" << (wall >= classified ? wall - classified : 0)
                << ",\"read_requested_bytes\":" << read_bytes << ",\"transfer_logical_bytes\":" << transfer_bytes
                << ",\"completed_tensors\":" << completed << ",\"active\":";
            write_location(out, active);
            out << ",\"operations\":{";
            bool separator = false;
            for (size_t i = 0; i < operations.size(); ++i) {
                const auto & stats = operations[i];
                if (stats.calls == 0) {
                    continue;
                }
                out << (separator ? ",\"" : "\"") << operation_names[i] << "\":{\"calls\":" << stats.calls
                    << ",\"bytes\":" << stats.bytes << ",\"sum_us\":" << stats.sum_us << ",\"max_us\":" << stats.max_us
                    << ",\"interval_max_us\":" << stats.interval_max_us;
                if (summary) {
                    out << ",\"histogram\":[";
                    for (size_t bin = 0; bin < stats.histogram.size(); ++bin) {
                        if (bin != 0) {
                            out << ',';
                        }
                        out << stats.histogram[bin];
                    }
                    out << ']';
                }
                out << '}';
                separator = true;
            }
            out << '}';
            if (summary) {
                out << ",\"status\":\"" << status << "\",\"long_waits\":[";
                auto sorted = longest;
                std::sort(sorted.begin(), sorted.end(),
                    [](const long_wait & a, const long_wait & b) { return a.duration_us > b.duration_us; });
                for (size_t i = 0; i < sorted.size() && sorted[i].duration_us != 0; ++i) {
                    const auto & item = sorted[i];
                    out << (i ? ",{" : "{") << "\"op\":\"" << operation_names[size_t(item.op)]
                        << "\",\"start_us\":" << item.start_us << ",\"duration_us\":" << item.duration_us << ",\"position\":";
                    write_location(out, item.pos);
                    out << '}';
                }
                out << ']';
            }
        });
    }

    const session & load;
    size_t index;
    const char * buffer_type;
    int64_t started;
    int64_t last_progress;
    const char * route = "upload_setup";
    const char * status = "failed";
    location active;
    uint64_t completed = 0;
    std::array<statistics, size_t(operation::count)> operations{};
    std::array<long_wait, long_wait_count> longest{};
};

template <typename Fn>
inline decltype(auto) measure(group * diag, operation op, Fn && fn, uint64_t bytes = 0, const location & pos = {}) {
    if (diag == nullptr) {
        return std::forward<Fn>(fn)();
    }
    struct timer {
        group & diag;
        operation op;
        const location & pos;
        uint64_t bytes;
        int64_t start;

        ~timer() {
            diag.record(op, pos, bytes, start, diag.now());
        }
    } timing{*diag, op, pos, bytes, diag->now()};
    return std::forward<Fn>(fn)();
}

} // namespace llama_load_diag
