#include "../../../ggml/src/ggml-mtp-diag.h"
#include <cassert>
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

static int clock_calls = 0;
extern "C" int64_t ggml_time_us() {
    ++clock_calls;
    return std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}
static std::vector<std::string> records;
static void emit(const char * line) { records.emplace_back(line); }
int main(int argc, char ** argv) {
    const bool off = argc > 1 && std::string(argv[1]) == "off";
    {
        mtp_diag::scope outer("server", "target_evaluation", nullptr, "target", emit, "generation");
        outer.add("n_tokens", int64_t(3));
        {
            mtp_diag::scope child("memory", "layout", nullptr, "unknown", emit);
            child.add("copied_cells", int64_t(256000));
        }
    }
    if (off) {
        assert(records.empty());
        assert(clock_calls == 0);
        return 0;
    }
    assert(records.size() == 4);
    assert(records[1].find("phase=generation") != std::string::npos);
    assert(records[2].find("copied_cells=256000") != std::string::npos);
    for (const auto & line : records) { std::cout << line; }
    if (argc > 1 && std::string(argv[1]) == "throw") {
        try {
            mtp_diag::scope failing("common", "process", nullptr, "draft", emit);
            throw std::runtime_error("test");
        } catch (const std::runtime_error &) {}
        assert(records.back().find("complete=0") != std::string::npos);
    }
}
