#pragma once

// Private, default-off wall diagnostics. No model/cache mutation or global GPU waits.
#include "ggml.h"
#include <atomic>
#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <functional>
#include <memory>
#include <thread>

namespace mtp_diag {
using logger = void (*)(const char *);
enum class mode { off, wall, sync };

inline mode setting() {
    static const mode value = [] {
        const char * v = std::getenv("LLAMA_MTP_DIAG");
        if (!v || !*v || !std::strcmp(v, "0") || !std::strcmp(v, "off")) { return mode::off; }
        if (!std::strcmp(v, "wall")) { return mode::wall; }
        if (!std::strcmp(v, "sync")) { return mode::sync; }
        std::fprintf(stderr, "mtp_diag: invalid LLAMA_MTP_DIAG='%s'; disabled\n", v);
        return mode::off;
    }();
    return value;
}
inline bool enabled() { return setting() != mode::off; }
inline bool synchronized() { return setting() == mode::sync; }

class scope {
public:
    scope(const char * domain, const char * event, const void * ctx, const char * role,
          logger emit, const char * phase = nullptr) : emit_(emit) {
        if (!enabled()) { return; }
        data_.reset(new data);
        data_->domain = domain; data_->event = event; data_->ctx = ctx; data_->role = role;
        data_->parent = current();
        data_->phase = phase ? phase : (data_->parent ? data_->parent->data_->phase : "unknown");
        data_->thread = std::hash<std::thread::id>{}(std::this_thread::get_id());
        static std::atomic<uint64_t> next{0};
        std::snprintf(data_->id, sizeof(data_->id), "%s-%" PRId64 "-%" PRIu64,
                      data_->domain, ggml_time_us(), ++next);
        data_->exceptions = std::uncaught_exceptions();
        current() = this;
        data_->start = ggml_time_us();
        emit_record("begin", 0, 0);
        data_->start = ggml_time_us(); // begin formatting is outside this operation's timer
        data_->active = true;
    }
    ~scope() { finish(); }
    scope(const scope &) = delete;
    scope & operator=(const scope &) = delete;
    bool active() const { return data_ && data_->active; }
    void add(const char * key, int64_t value) {
        if (!active()) { return; }
        char text[48]; std::snprintf(text, sizeof(text), "%" PRId64, value);
        add(key, text);
    }
    void add(const char * key, const char * value) {
        if (!active()) { return; }
        const int n = std::snprintf(data_->fields + data_->used, sizeof(data_->fields) - data_->used, " %s=%s", key, value);
        if (n < 0 || size_t(n) >= sizeof(data_->fields) - data_->used) { data_->truncated = true; return; }
        data_->used += size_t(n);
    }
    void pointer(const char * key, const void * value) {
        if (!active()) { return; }
        char text[32]; std::snprintf(text, sizeof(text), "%p", value); add(key, text);
    }
    void status(int rc) { if (active()) { data_->rc = rc; } }
    void finish() {
        if (!active()) { return; }
        const int64_t end = ggml_time_us();
        const bool complete = std::uncaught_exceptions() <= data_->exceptions && data_->rc == 0 && !data_->truncated;
        emit_record("end", end, complete ? 1 : 0);
        current() = data_->parent;
        data_->active = false;
    }
private:
    static scope * & current() { static thread_local scope * value = nullptr; return value; }
    void emit_record(const char * kind, int64_t end, int complete) {
        char record[2048];
        std::snprintf(record, sizeof(record),
            "mtp_diag v=1 kind=%s mode=%s domain=%s event=%s id=%s parent=%s ctx=%p role=%s phase=%s "
            "thread=%zu t0_us=%" PRId64 " t1_us=%" PRId64 " elapsed_us=%" PRId64 " rc=%d complete=%d%s\n",
            kind, synchronized() ? "sync" : "wall", data_->domain, data_->event, data_->id, data_->parent ? data_->parent->data_->id : "none",
            data_->ctx, data_->role, data_->phase, data_->thread, data_->start, end, end ? end - data_->start : 0, data_->rc, complete, data_->fields);
        emit_(record);
    }
    struct data {
        bool active = false, truncated = false;
        const char * domain = "unknown", * event = "unknown", * role = "unknown", * phase = "unknown";
        const void * ctx = nullptr;
        scope * parent = nullptr;
        char id[96] = {}, fields[1024] = {};
        size_t thread = 0, used = 0;
        int64_t start = 0;
        int rc = 0, exceptions = 0;
    };
    logger emit_;
    std::unique_ptr<data> data_;
};
} // namespace mtp_diag
