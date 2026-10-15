// SPDX-License-Identifier: MIT
//
// Evo-X2 ADLX GPU monitor.
// Investigation tool for validating AMD ADLX performance metrics over Windows RDP.

#include "SDK/ADLXHelper/Windows/Cpp/ADLXHelper.h"
#include "SDK/Include/IPerformanceMonitoring3.h"

#include <windows.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>

using namespace adlx;

namespace {

std::atomic<bool> g_stop_requested{false};

BOOL WINAPI console_handler(DWORD ctrl_type) {
    switch (ctrl_type) {
        case CTRL_C_EVENT:
        case CTRL_BREAK_EVENT:
        case CTRL_CLOSE_EVENT:
            g_stop_requested.store(true);
            return TRUE;
        default:
            return FALSE;
    }
}

struct Options {
    std::filesystem::path output = "adlx-gpu-metrics.csv";
    int duration_seconds = 30;
    int interval_ms = 2000;
    int gpu_index = 0;
    bool list_gpus = false;
};

struct MetricSupport {
    bool usage = false;
    bool clock = false;
    bool vram_clock = false;
    bool temperature = false;
    bool hotspot = false;
    bool power = false;
    bool vram = false;
    bool total_board_power = false;
};

struct Sample {
    ADLX_RESULT result = ADLX_FAIL;
    std::optional<adlx_int64> adlx_timestamp_ms;
    std::optional<adlx_double> usage_pct;
    std::optional<adlx_int> clock_mhz;
    std::optional<adlx_int> vram_clock_mhz;
    std::optional<adlx_double> temperature_c;
    std::optional<adlx_double> hotspot_c;
    std::optional<adlx_double> power_w;
    std::optional<adlx_int> vram_mb;
    std::optional<adlx_double> total_board_power_w;
};

[[noreturn]] void usage_error(const std::string & message) {
    throw std::runtime_error(message + "\nUse --help for usage.");
}

void print_usage(const char * exe) {
    std::cout
        << "Evo-X2 ADLX GPU monitor\n\n"
        << "Usage:\n"
        << "  " << exe << " [options]\n\n"
        << "Options:\n"
        << "  --output <path>       CSV output path (default: adlx-gpu-metrics.csv)\n"
        << "  --duration <seconds>  Run duration; 0 means until Ctrl+C (default: 30)\n"
        << "  --interval-ms <ms>    Sampling interval, minimum 100 ms (default: 2000)\n"
        << "  --gpu-index <index>   Zero-based GPU index (default: 0)\n"
        << "  --list-gpus           List GPUs visible to ADLX and exit\n"
        << "  --help                Show this help\n";
}

int parse_int(const std::string & value, const char * option_name) {
    std::size_t used = 0;
    int parsed = 0;
    try {
        parsed = std::stoi(value, &used);
    } catch (...) {
        usage_error(std::string(option_name) + " requires an integer");
    }
    if (used != value.size()) {
        usage_error(std::string(option_name) + " requires an integer");
    }
    return parsed;
}

Options parse_options(int argc, char ** argv) {
    Options options;

    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];

        auto require_value = [&](const char * option_name) -> std::string {
            if (i + 1 >= argc) {
                usage_error(std::string(option_name) + " requires a value");
            }
            return argv[++i];
        };

        if (arg == "--output") {
            options.output = require_value("--output");
        } else if (arg == "--duration") {
            options.duration_seconds = parse_int(require_value("--duration"), "--duration");
        } else if (arg == "--interval-ms") {
            options.interval_ms = parse_int(require_value("--interval-ms"), "--interval-ms");
        } else if (arg == "--gpu-index") {
            options.gpu_index = parse_int(require_value("--gpu-index"), "--gpu-index");
        } else if (arg == "--list-gpus") {
            options.list_gpus = true;
        } else if (arg == "--help" || arg == "-h" || arg == "/?") {
            print_usage(argv[0]);
            std::exit(0);
        } else {
            usage_error("Unknown option: " + arg);
        }
    }

    if (options.duration_seconds < 0) {
        usage_error("--duration must be >= 0");
    }
    if (options.interval_ms < 100) {
        usage_error("--interval-ms must be >= 100");
    }
    if (options.gpu_index < 0) {
        usage_error("--gpu-index must be >= 0");
    }

    return options;
}

std::string local_timestamp() {
    SYSTEMTIME st{};
    GetLocalTime(&st);

    char buffer[64]{};
    std::snprintf(
        buffer,
        sizeof(buffer),
        "%04u-%02u-%02uT%02u:%02u:%02u.%03u",
        st.wYear,
        st.wMonth,
        st.wDay,
        st.wHour,
        st.wMinute,
        st.wSecond,
        st.wMilliseconds);
    return buffer;
}

std::string csv_escape(const std::string & value) {
    if (value.find_first_of(",\"\r\n") == std::string::npos) {
        return value;
    }

    std::string escaped;
    escaped.reserve(value.size() + 2);
    escaped.push_back('"');
    for (const char c : value) {
        if (c == '"') {
            escaped.push_back('"');
        }
        escaped.push_back(c);
    }
    escaped.push_back('"');
    return escaped;
}

template <typename T>
std::string optional_integer(const std::optional<T> & value) {
    return value ? std::to_string(*value) : std::string();
}

std::string optional_decimal(const std::optional<adlx_double> & value) {
    if (!value) {
        return {};
    }

    std::ostringstream out;
    out << std::fixed << std::setprecision(3) << *value;
    return out.str();
}

MetricSupport query_support(const IADLXGPUMetricsSupportPtr & support) {
    MetricSupport result;
    adlx_bool supported = false;

    supported = false;
    if (ADLX_SUCCEEDED(support->IsSupportedGPUUsage(&supported))) {
        result.usage = supported;
    }

    supported = false;
    if (ADLX_SUCCEEDED(support->IsSupportedGPUClockSpeed(&supported))) {
        result.clock = supported;
    }

    supported = false;
    if (ADLX_SUCCEEDED(support->IsSupportedGPUVRAMClockSpeed(&supported))) {
        result.vram_clock = supported;
    }

    supported = false;
    if (ADLX_SUCCEEDED(support->IsSupportedGPUTemperature(&supported))) {
        result.temperature = supported;
    }

    supported = false;
    if (ADLX_SUCCEEDED(support->IsSupportedGPUHotspotTemperature(&supported))) {
        result.hotspot = supported;
    }

    supported = false;
    if (ADLX_SUCCEEDED(support->IsSupportedGPUPower(&supported))) {
        result.power = supported;
    }

    supported = false;
    if (ADLX_SUCCEEDED(support->IsSupportedGPUVRAM(&supported))) {
        result.vram = supported;
    }

    supported = false;
    if (ADLX_SUCCEEDED(support->IsSupportedGPUTotalBoardPower(&supported))) {
        result.total_board_power = supported;
    }

    return result;
}

Sample read_sample(
    const IADLXPerformanceMonitoringServicesPtr & perf,
    const IADLXGPUPtr & gpu,
    const MetricSupport & support) {

    Sample sample;
    IADLXGPUMetricsPtr metrics;

    sample.result = perf->GetCurrentGPUMetrics(gpu, &metrics);
    if (ADLX_FAILED(sample.result) || !metrics) {
        return sample;
    }

    {
        adlx_int64 value = 0;
        if (ADLX_SUCCEEDED(metrics->TimeStamp(&value))) {
            sample.adlx_timestamp_ms = value;
        }
    }

    if (support.usage) {
        adlx_double value = 0;
        if (ADLX_SUCCEEDED(metrics->GPUUsage(&value))) {
            sample.usage_pct = value;
        }
    }

    if (support.clock) {
        adlx_int value = 0;
        if (ADLX_SUCCEEDED(metrics->GPUClockSpeed(&value)) {
            sample.clock_mhz = value;
        }
    }

    if (support.vram_clock) {
        adlx_int value = 0;
        if (ADLX_SUCCEEDED(metrics->GPUU”SPÛØÚÔÜYY
	˜[YJJJHÂˆØ[\Kœ˜[WØÛØÚ×ÛZˆH˜[YNÂˆBˆB‚ˆYˆ
İ\Ü[\\˜]\™JHÂˆYÙİX›H˜[YHHÂˆYˆ
QÔÕPĞÑQQQ
Y]šXÜËO‘ÔU[\\˜]\™J	˜[YJJJHÂˆØ[\K[\\˜]\™WØÈH˜[YNÂˆBˆB‚ˆYˆ
İ\ÜšİÜİ
HÂˆYÙİX›H˜[YHHÂˆYˆ
QÔÕPĞÑQQQ
Y]šXÜËO‘ÔRİÜİ[\\˜]\™J	˜[YJJJHÂˆØ[\KšİÜİØÈH˜[YNÂˆBˆB‚ˆYˆ
İ\ÜœİÙ\ŠHÂˆYÙİX›H˜[YHHÂˆYˆ
QÔÕPĞÑQQQ
Y]šXÜËO‘ÔTİÙ\Š	˜[YJJJHÂˆØ[\KœİÙ\—İÈH˜[YNÂˆBˆB‚ˆYˆ
İ\Üœ˜[JHÂˆYÚ[˜[YHHÂˆYˆ
QÔÕPĞÑQQQ
Y]šXÜËO‘ÔU”SJ	˜[YJJJHÂˆØ[\Kœ˜[WÛXˆH˜[YNÂˆBˆB‚ˆYˆ
İ\Üİ[Ø›Ø\™ÜİÙ\ŠHÂˆYÙİX›H˜[YHHÂˆYˆ
QÔÕPĞÑQQQ
Y]šXÜËO‘ÔUİ[›Ø\™İÙ\Š	˜[YJJHÂˆØ[\Kİ[Ø›Ø\™ÜİÙ\—İÈH˜[YNÂˆBˆB‚ˆ™]\›ˆØ[\NÂŸB‚›ÚYš[Üİ\Ü
ÛÛœİY]šXÔİ\Ü	ˆÊHÂˆİ˜Ûİ]ˆ”İ\ÜYY]šXÜÎˆ‚ˆˆ\ØYÙOHˆË\ØYÙBˆˆÛØÚÏHˆË˜ÛØÚÂˆˆœ˜[WØÛØÚÏHˆËœ˜[WØÛØÚÂˆˆ[\HˆË[\\˜]\™BˆˆİÜİHˆËšİÜİˆˆİÙ\HˆËœİÙ\‚ˆˆœ˜[OHˆËœ˜[Bˆˆİ[Ø›Ø\™ÜİÙ\HˆËİ[Ø›Ø\™ÜİÙ\‚ˆ—ˆÂŸB‚š[[—İÚ]ØY
Q[\ˆ	ˆ[\‹ÛÛœİÜ[ÛœÈ	ˆÜ[ÛœÊHÂˆPQÔS\İˆÜ\ÎÂˆQÔ‘TÕS™\ÈH[\‹‘Ù]Ş\İ[TÙ\šXÙ\Ê
KO‘Ù]Ô\Ê	™Ü\ÊNÂˆYˆ
QÑRSQ
™\ÊHYÜ\ÈÜ\ËO‘[\J
JHÂˆİ˜Ù\œˆQÙ]Ô\È˜Z[YÜˆ™]\›™Y›ÈÔ\Ëˆ™\İ[Hˆİ]X×ØØ\İ[Š™\ÊH—ˆÂˆ™]\›ˆÎÂˆB‚ˆİ˜Ûİ]‘Ô\Èš\ÚX›HÈQˆˆÜ\ËO”Ú^™J
H—ˆÂˆ›Üˆ
YİZ[ØØ][ÛˆHÜ\ËO™YÚ[Š
KÜ™[˜[HÈØØ][ÛˆOHÜ\ËO‘[™

NÈ
ÊÛØØ][Û‹
ÊÛÜ™[˜[
HÂˆPQÔTˆÜNÂˆÛÛœİQÔ‘TÕSÜWÜ™\ÈHÜ\ËO]
ØØ][Û‹	™ÜJNÂˆYˆ
QÑRSQ
ÜWÜ™\ÊHYÜJHÂˆİ˜Ûİ]ˆÈˆÜ™[˜[—H˜Z[YÈ]Y\Oˆ™\İ[H‚ˆİ]X×ØØ\İ[ŠÜWÜ™\ÊH—ˆÂˆÛÛ[YNÂˆB‚ˆÛÛœİÚ\ˆ
ˆ˜[YHH[ÂˆÛÛœİQÔ‘TÕS˜[YWÜ™\ÈHÜKO“˜[YJ	›˜[YJNÂˆİ˜Ûİ]ˆÈˆÜ™[˜[—H‚ˆ

QÔÕPĞÑQQQ
˜[YWÜ™\ÊH	‰ˆ˜[YJHÈ˜[YHˆ[šÛ›İÛˆŠBˆ—ˆÂˆB‚ˆYˆ
Ü[ÛœË›\İÙÜ\ÊHÂˆ™]\›ˆÂˆB‚ˆYˆ
İ]X×ØØ\İYİZ[ŠÜ[ÛœË™ÜWÚ[™^
HHÜ\ËO”Ú^™J
JHÂˆİ˜Ù\œˆ”™\]Y\İYÔH[™^ˆÜ[ÛœË™ÜWÚ[™^ˆˆ]Q™\ÜÈˆÜ\ËO”Ú^™J
HˆÔJÊK—ˆÂˆ™]\›ˆÂˆB‚ˆÛÛœİYİZ[ØØ][ÛˆHÜ\ËO™YÚ[Š
H
Èİ]X×ØØ\İYİZ[ŠÜ[ÛœË™ÜWÚ[™^
NÂˆPQÔTˆÜNÂˆ™\ÈHÜ\ËO]
ØØ][Û‹	™ÜJNÂˆYˆ
QÑRSQ
™\ÊHYÜJHÂˆİ˜Ù\œˆ‘˜Z[YÈÙ]ÔH[™^ˆÜ[ÛœË™ÜWÚ[™^ˆ‹ˆ™\İ[Hˆİ]X×ØØ\İ[Š™\ÊH—ˆÂˆ™]\›ˆNÂˆB‚ˆÛÛœİÚ\ˆ
ˆÜWÛ˜[YWÜ˜]ÈH[ÂˆÛÛœİQÔ‘TÕS˜[YWÜ™\ÈHÜKO“˜[YJ	™ÜWÛ˜[YWÜ˜]ÊNÂˆÛÛœİİœİš[™ÈÜWÛ˜[YHBˆ
QÔÕPĞÑQQQ
˜[YWÜ™\ÊH	‰ˆÜWÛ˜[YWÜ˜]ÊHÈÜWÛ˜[YWÜ˜]Èˆ[šÛ›İÛˆÂ‚ˆPQ\™›Ü›X[˜ÙS[Ûš]Üš[™ÔÙ\šXÙ\Ôˆ\™Âˆ™\ÈH[\‹‘Ù]Ş\İ[TÙ\šXÙ\Ê
KO‘Ù]\™›Ü›X[˜ÙS[Ûš]Üš[™ÔÙ\šXÙ\Ê	œ\™ŠNÂˆYˆ
QÑRSQ
™\ÊH\\™ŠHÂˆİ˜Ù\œˆ‘Ù]\™›Ü›X[˜ÙS[Ûš]Üš[™ÔÙ\šXÙ\È˜Z[Yˆ™\İ[H‚ˆİ]X×ØØ\İ[Š™\ÊH—ˆÂˆ™]\›ˆÂˆB‚ˆPQÔSY]šXÜÔİ\Üˆİ\ÜÚ[\™˜XÙNÂˆ™\ÈH\™‹O‘Ù]İ\ÜYÔSY]šXÜÊÜK	œİ\ÜÚ[\™˜XÙJNÂˆYˆ
QÑRSQ
™\ÊH\İ\ÜÚ[\™˜XÙJHÂˆİ˜Ù\œˆ‘Ù]İ\ÜYÔSY]šXÜÈ˜Z[Yˆ™\İ[Hˆİ]X×ØØ\İ[Š™\ÊH—ˆÂˆ™]\›ˆÎÂˆB‚ˆÛÛœİY]šXÔİ\Üİ\ÜH]Y\WÜİ\Ü
İ\ÜÚ[\™˜XÙJNÂˆš[Üİ\Ü
İ\Ü
NÂ‚ˆÓÔ‘Ù\ÜÚ[Û—ÚYHÂˆÛÛœİ“ÓÓÛİÜÙ\ÜÚ[ÛˆH›ØÙ\ÜÒYÔÙ\ÜÚ[Û’Y
Ù]İ\œ™[›ØÙ\ÜÒY

K	œÙ\ÜÚ[Û—ÚY
NÂˆÛÛœİ›ÛÛ™[[İWÜÙ\ÜÚ[ÛˆHÙ]Ş\İ[SY]šXÜÊÓWÔ‘SSÕTÑTÔÒSÓŠHOHÂ‚ˆİ˜Ûİ]”Ù[XİYÔNˆÈˆÜ[ÛœË™ÜWÚ[™^—HˆÜWÛ˜[YH—ˆÂˆİ˜Ûİ]•Ú[™İÜÈÙ\ÜÚ[ÛˆYH‚ˆ
ÛİÜÙ\ÜÚ[ÛˆÈİ×Üİš[™ÊÙ\ÜÚ[Û—ÚY
Hˆİœİš[™Ê[šÛ›İÛˆŠJBˆˆ™[[İOHˆ
™[[İWÜÙ\ÜÚ[ÛˆÈY\Èˆˆ››ÈŠH—ˆÂˆİ˜Ûİ]”Ø[\[™Îˆ[\˜[HˆÜ[ÛœËš[\˜[Û\Âˆˆ\È\˜][ÛHˆÜ[ÛœË™\˜][Û—ÜÙXÛÛ™ÂˆˆÈİ]]HˆÜ[ÛœË›İ]]œİš[™Ê
H—ˆÂ‚ˆYˆ
ÛÛœİ]]È\™[HÜ[ÛœË›İ]]œ\™[Ü]

NÈ\\™[™[\J
JHÂˆİ™\œ›Ü—ØÛÙHXÎÂˆİ™š[\Ş\İ[N˜Ü™X]WÙ\™XİÜšY\Ê\™[XÊNÂˆYˆ
XÊHÂˆİ˜Ù\œˆ‘˜Z[YÈÜ™X]Hİ]]\™XİÜNˆˆ\™[œİš[™Ê
Bˆˆ\œ›ÜHˆXË›Y\ÜØYÙJ
H—ˆÂˆ™]\›ˆÂˆBˆB‚ˆİ›Ùœİ™X[HÜİŠÜ[ÛœË›İ]]İš[ÜÎ›İ]İš[ÜÎ[˜ÊNÂˆYˆ
XÜİŠHÂˆİ˜Ù\œˆ‘˜Z[YÈÜ[ˆİ]]ÔÕˆˆÜ[ÛœË›İ]]œİš[™Ê
H—ˆÂˆ™]\›ˆNÂˆB‚ˆÜİˆ[Y\İ[\ÛØØ[[\ÙYÛ\ËYİ[Y\İ[\Û\ËÚ[™İÜ×ÜÙ\ÜÚ[Û—ÚY™[[İWÜÙ\ÜÚ[Û‹‚ˆ™ÜWÚ[™^ÜWÛ˜[YKÜWİ\ØYÙWÜİÜWØÛØÚ×ÛZ‹ÜWİœ˜[WØÛØÚ×ÛZ‹‚ˆ™ÜWİ[\ØËÜWÚİÜİØËÜWÜİÙ\—İËÜWİœ˜[WÛX‹İ[Ø›Ø\™ÜİÙ\—İËYÜ™\İ[ˆÂˆÜİ‹™›\Ú

NÂ‚ˆÛÛœİ]]Èİ\Hİ˜Ú›Û›ÎœİXYWØÛØÚÎ››İÊ
NÂˆÛÛœİ]]È\˜][Û—Û\ÈHİ]X×ØØ\İÛ™ÈÛ™ÏŠÜ[ÛœË™\˜][Û—ÜÙXÛÛ™ÊH
ˆLÂˆİZ[İØ[\WÚ[™^HÂ‚ˆÚ[H
Y×ÜİÜÜ™\]Y\İY›ØY

JHÂˆÛÛœİ]]È›İÈHİ˜Ú›Û›ÎœİXYWØÛØÚÎ››İÊ
NÂˆÛÛœİ]]È[\ÙYÛ\ÈBˆİ˜Ú›Û›Î™\˜][Û—ØØ\İİ˜Ú›Û›Î›Z[\ÙXÛÛ™ÏŠ›İÈHİ\
K˜Ûİ[

NÂ‚ˆYˆ
Ü[ÛœË™\˜][Û—ÜÙXÛÛ™Èˆ	‰ˆ[\ÙYÛ\Èˆ\˜][Û—Û\È	‰ˆØ[\WÚ[™^ˆ
HÂˆœ™XZÎÂˆB‚ˆÛÛœİİœİš[™È[Y\İ[\HØØ[İ[Y\İ[\

NÂˆÛÛœİØ[\HØ[\HH™XYÜØ[\J\™‹ÜKİ\Ü
NÂ‚ˆÜİ‚ˆÜİ—Ù\ØØ\J[Y\İ[\
H	Ë	Âˆ[\ÙYÛ\È	Ë	ÂˆÜ[Û˜[Ú[YÙ\ŠØ[\K˜Yİ[Y\İ[\Û\ÊH	Ë	Âˆ
ÛİÜÙ\ÜÚ[ÛˆÈİ×Üİš[™ÊÙ\ÜÚ[Û—ÚY
Hˆİœİš[™Ê
JH	Ë	Âˆ
™[[İWÜÙ\ÜÚ[ÛˆÈHˆ
H	Ë	ÂˆÜ[ÛœË™ÜWÚ[™^	Ë	ÂˆÜİ—Ù\ØØ\JÜWÛ˜[YJH	Ë	ÂˆÜ[Û˜[ÙXÚ[X[
Ø[\K\ØYÙWÜİ
H	Ë	ÂˆÜ[Û˜[Ú[YÙ\ŠØ[\K˜ÛØÚ×ÛZŠH	Ë	ÂˆÜ[Û˜[Ú[YÙ\ŠØ[\Kœ˜[WØÛØÚ×ÛZŠH	Ë	ÂˆÜ[Û˜[ÙXÚ[X[
Ø[\K[\\˜]\™WØÊH	Ë	ÂˆÜ[Û˜[ÙXÚ[X[
Ø[\KšİÜİØÊH	Ë	ÂˆÜ[Û˜[ÙXÚ[X[
Ø[\KœİÙ\—İÊH	Ë	ÂˆÜ[Û˜[Ú[YÙ\ŠØ[\Kœ˜[WÛXŠH	Ë	ÂˆÜ[Û˜[ÙXÚ[X[
Ø[\Kİ[Ø›Ø\™ÜİÙ\—İÊH	Ë	Âˆİ]X×ØØ\İ[ŠØ[\Kœ™\İ[
Bˆ	×‰ÎÂˆÜİ‹™›\Ú

NÂ‚ˆYˆ
QÑRSQ
Ø[\Kœ™\İ[
JHÂˆİ˜Ù\œˆ”Ø[\HˆØ[\WÚ[™^ˆˆ˜Z[YˆQ™\İ[Hˆİ]X×ØØ\İ[ŠØ[\Kœ™\İ[
H—ˆÂˆB‚ˆYˆ
Ü[ÛœË™\˜][Û—ÜÙXÛÛ™Èˆ	‰ˆ[\ÙYÛ\ÈH\˜][Û—Û\ÊHÂˆœ™XZÎÂˆB‚ˆ
ÊÜØ[\WÚ[™^ÂˆÛÛœİ]]È™^Bˆİ\
Èİ˜Ú›Û›Î›Z[\ÙXÛÛ™Êİ]X×ØØ\İÛ™ÈÛ™ÏŠØ[\WÚ[™^
H
ˆÜ[ÛœËš[\˜[Û\ÊNÂˆİ\×İ™XYœÛY\İ[[
™^
NÂˆB‚ˆİ˜Ûİ]‘š[š\ÚYˆÔÕˆˆÜ[ÛœË›İ]]œİš[™Ê
H—ˆÂˆ™]\›ˆÂŸB‚ŸHËÈ˜[Y\ÜXÙB‚š[XZ[Š[\™ØËÚ\ˆ
Šˆ\™İŠHÂˆHÂˆÛÛœİÜ[ÛœÈÜ[ÛœÈH\œÙWÛÜ[ÛœÊ\™ØË\™İŠNÂ‚ˆÙ]ÛÛœÛÛPİ›[™\ŠÛÛœÛÛWÚ[™\‹•QJNÂ‚ˆQ[\ˆ[\ÂˆÛÛœİQÔ‘TÕS[š]Ü™\ÈH[\‹’[š]X[^™J
NÂˆYˆ
QÑRSQ
[š]Ü™\ÊJHÂˆİ˜Ù\œˆQ[š]X[^˜][Ûˆ˜Z[Yˆ™\İ[Hˆİ]X×ØØ\İ[Š[š]Ü™\ÊH—ˆÂˆ™]\›ˆÂˆB‚ˆÛÛœİÚ\ˆ
ˆYİ™\œÚ[ÛˆH[\‹”]Y\U™\œÚ[ÛŠ
NÂˆİ˜Ûİ]Q[[YH™\œÚ[Ûˆ‚ˆ
Yİ™\œÚ[ÛˆÈYİ™\œÚ[Ûˆˆ[šÛ›İÛˆŠH—ˆÂ‚ˆËÈ[QÛX\Ú[\œÈ\™HØÛÜY[œÚYH[—İÚ]ØY[™\™H™[X\ÙYˆËÈ™Y›Ü™H\›Z[˜]J
H[›ØYÈHQ[[YK‚ˆÛÛœİ[[—Ü™\İ[H[—İÚ]ØY
[\‹Ü[ÛœÊNÂ‚ˆÛÛœİQÔ‘TÕS\›WÜ™\ÈH[\‹•\›Z[˜]J
NÂˆYˆ
QÑRSQ
\›WÜ™\ÊJHÂˆİ˜Ù\œˆQ\›Z[˜][Ûˆ˜Z[Yˆ™\İ[Hˆİ]X×ØØ\İ[Š\›WÜ™\ÊH—ˆÂˆ™]\›ˆ[—Ü™\İ[OHÈLˆ[—Ü™\İ[ÂˆB‚ˆ™]\›ˆ[—Ü™\İ[ÂˆHØ]Ú
ÛÛœİİ™^Ù\[Ûˆ	ˆ^
HÂˆİ˜Ù\œˆ™\œ›Üˆˆ^Ú]

H—ˆÂˆ™]\›ˆNÂˆBŸB