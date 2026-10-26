#include "../src/llama-mtp-indexer-policy.h"

#include <array>
#include <cstdio>
#include <cstdlib>
#include <cstring>

static void check(bool ok, const char * name) {
    if (!ok) {
        std::fprintf(stderr, "MTP indexer policy: FAIL: %s\n", name);
        std::exit(1);
    }
}

int main() {
    // Sidecar metadata: positive trunk ratios must not disqualify the dense head.
    std::array<uint32_t, 49> ratios{};
    for (size_t i = 3; i < 48; i += 4) { ratios[i] = 4; }
    auto run = [&](const char * value, bool arch = true, bool mtp = true, bool idx = true,
                   uint32_t layers = 49, uint32_t heads = 1, size_t count = 49) {
        return llama_mtp_indexer::decide(value, arch, mtp, idx, layers, heads, ratios.data(), count);
    };
    const std::array<const char *, 8> disabled{{nullptr, "", "0", "off", "true", "01", " 1", "1 "}};
    for (const char * value : disabled) {
        const auto d = run(value);
        check(d.eligible && !d.requested && !d.enabled, "default/invalid values preserve cache");
    }
    auto d = run("1");
    check(d.enabled && d.eligible && d.layer == 48 && d.ratio == 0, "dense head with sparse trunk");
    check(!run("1", false).enabled, "other architecture");
    check(!run("1", true, false).enabled, "target context");
    check(!run("1", true, true, false).enabled, "indexer already absent");
    check(!run("1", true, true, true, 49, 0).enabled, "missing head");
    check(!run("1", true, true, true, 49, 2).enabled, "multiple heads");
    check(!run("1", true, true, true, 0, 1).enabled, "no layers/underflow");
    check(!run("1", true, true, true, 49, 1, 48).enabled, "short ratio array");
    check(!llama_mtp_indexer::decide("1", true, true, true, 49, 1, nullptr, 49).enabled,
          "null ratio array");
    ratios[48] = 4;
    d = run("1");
    check(!d.eligible && !d.enabled && d.ratio == 4 && std::strcmp(d.reason, "compressed") == 0,
          "positive head retains QSA cache");
    std::puts("MTP indexer policy: PASS");
    return 0;
}
