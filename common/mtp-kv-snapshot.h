#pragma once

// Opt-in diagnostic only. Captures the Draft sequence state AFTER a successful
// MTP catch-up llama_process(), before any subsequent draft/verify operations.
// Uses the public, synchronous state serializer instead of reading Vulkan
// buffers or walking ggml cache slots with a second, fragile implementation.
//
// The seq-state file contains the attention cache (cell metadata, K then V),
// followed by the recurrent state and optional indexer suffix. The analysis
// tool reads ONLY the attention K/V section and aligns rows by token position.
// Never use this instrumentation for PP/TG benchmark measurements.

#include "llama.h"

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <vector>

namespace mtp_kv_snapshot {

class recorder {
public:
    recorder() {
        const char * dir = std::getenv("LLAMA_MTP_KV_SNAPSHOT_DIR");
        const char * tag = std::getenv("LLAMA_MTP_KV_SNAPSHOT_TAG");
        const char * positions = std::getenv("LLAMA_MTP_KV_SNAPSHOT_POSITIONS");

        if (!dir && !tag && !positions) {
            return; // the normal hot path remains inert
        }

        if (!dir || !*dir || !tag || !*tag || !positions || !*positions) {
            error_ = "DIR, TAG and POSITIONS must all be set";
            enabled_ = true;
            return;
        }

        for (const unsigned char c : std::string(tag)) {
            if (!std::isalnum(c) && c != '_' && c != '-') {
                error_ = "TAG must contain only ASCII letters/digits/_/-";
                enabled_ = true;
                return;
            }
        }

        directory_ = std::filesystem::path(dir);
        tag_ = tag;

        std::string csv(positions);
        size_t cur = 0;
        try {
            while (cur < csv.size()) {
                const size_t end = csv.find(',', cur);
                std::string token = csv.substr(cur, end == std::string::npos ? end : end - cur);

                const auto first = token.find_first_not_of(" \t");
                const auto last  = token.find_last_not_of(" \t");
                if (first == std::string::npos) {
                    error_ = "empty position threshold";
                    break;
                }
                token = token.substr(first, last - first + 1);

                size_t parsed = 0;
                const auto threshold = std::stoull(token, &parsed, 10);
                if (parsed != token.size() || threshold == 0 || threshold > 1000000000ULL) {
                    error_ = "invalid position threshold";
                    break;
                }
                thresholds_.push_back(threshold);
                if (end == std::string::npos) {
                    break;
                }
                cur = end + 1;
            }
        } catch (...) {
            error_ = "invalid numeric position threshold";
        }

        std::sort(thresholds_.begin(), thresholds_.end());
        if (thresholds_.empty() ||
            std::adjacent_find(thresholds_.begin(), thresholds_.end()) != thresholds_.end()) {
            error_ = "thresholds must be nonempty and unique";
        }

        fired_.resize(thresholds_.size(), false);
        enabled_ = true;
    }

    // Called only after a successful Draft catch-up decode.
    // pos_end is zero-based, inclusive; threshold is one-based token count.
    bool capture(llama_context * ctx, llama_seq_id seq_id, int64_t pos_end, bool is_prompt) {
        if (!enabled_) {
            return true;
        }
        if (!error_.empty()) {
            std::fprintf(stderr, "mtp_kv_snapshot_v1 ERROR %s\n", error_.c_str());
            return false;
        }
        if (!is_prompt) {
            return true; // never trigger from speculative generation/rollback
        }
        if (seq_id != 0 || pos_end < 0) {
            std::fprintf(stderr, "mtp_kv_snapshot_v1 ERROR unsupported seq_id/position\n");
            return false; // initial diagnostic has a deliberately narrow single-seq contract
        }

        try {
            for (size_t i = 0; i < thresholds_.size(); ++i) {
                if (fired_[i] || (uint64_t) pos_end + 1 < thresholds_[i]) {
                    continue;
                }

                std::filesystem::create_directories(directory_);
                const auto absdir = std::filesystem::absolute(directory_);

                const std::string filename =
                    "draft-kv-" + tag_ + "-threshold-" + std::to_string(thresholds_[i]) +
                    "-pos-" + std::to_string(pos_end) + ".bin";

                const auto path = absdir / filename;
                if (std::filesystem::exists(path)) {
                    std::fprintf(stderr,
                        "mtp_kv_snapshot_v1 ERROR file already exists: %s (move/remove old output before rerun)\n",
                        path.string().c_str());
                    return false;
                }

                // Stream state to disk. This public API synchronizes the Draft
                // backend and serializes K/V + recurrent state without allocating
                // a huge additional host snapshot buffer. It must only be called
                // in diagnostic processes with known stable seq IDs.
                const size_t bytes = llama_state_seq_save_file(ctx, path.string().c_str(),
                                                              seq_id, nullptr, 0);
                if (bytes == 0) {
                    std::filesystem::remove(path);
                    std::fprintf(stderr,
                        "mtp_kv_snapshot_v1 ERROR state save failed tag=%s threshold=%llu pos=%lld\n",
                        tag_.c_str(), (unsigned long long) thresholds_[i], (long long) pos_end);
                    return false;
                }

                fired_[i] = true;
                std::fprintf(stderr,
                    "mtp_kv_snapshot_v1 OK tag=%s threshold=%llu pos=%lld seq=%d bytes=%zu path=%s\n",
                    tag_.c_str(), (unsigned long long) thresholds_[i], (long long) pos_end,
                    (int) seq_id, bytes, path.string().c_str());
            }
        } catch (const std::exception & e) {
            std::fprintf(stderr, "mtp_kv_snapshot_v1 ERROR %s\n", e.what());
            return false;
        }

        return true;
    }

private:
    bool enabled_ = false;
    std::string error_;
    std::filesystem::path directory_;
    std::string tag_;
    std::vector<uint64_t> thresholds_;
    std::vector<bool> fired_;
};

} // namespace mtp_kv_snapshot
