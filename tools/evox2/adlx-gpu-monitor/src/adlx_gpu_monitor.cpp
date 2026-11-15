// SPDX-License-Identifier: MIT
//
// Evo-X2 ADLX GPU monitor.
// Investigation tool for validating AMD ADLX performance metrics over Windows RDP.

#include "SDK/ADLXHelper/Windows/Cpp/ADLXHelper.h"
#include "SDK/Include/IPerformanceMonitoring.h"

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
    DWORD target_pid = 0;
    bool list_gpus = false;
};

struct MetricSupport {
    bool usage = false;
    ADLX_RESULT usage_result = ADLX_FAIL;
    bool clock = false;
    ADLX_RESULT clock_result = ADLX_FAIL;
    bool vram_clock = false;
    ADLX_RESULT vram_clock_result = ADLX_FAIL;
    bool temperature = false;
    ADLX_RESULT temperature_result = ADLX_FAIL;
    bool hotspot = false;
    ADLX_RESULT hotspot_result = ADLX_FAIL;
    bool power = false;
    ADLX_RESULT power_result = ADLX_FAIL;
    bool vram = false;
    ADLX_RESULT vram_result = ADLX_FAIL;
    bool total_board_power = false;
    ADLX_RESULT total_board_power_result = ADLX_FAIL;
};

struct Sample {
    ADLX_RESULT result = ADLX_FAIL;
    bool has_adlx_timestamp = false;
    adlx_int64 adlx_timestamp_ms = 0;
    bool has_usage = false;
    adlx_double usage_pct = 0;
    bool has_clock = false;
    adlx_int clock_mhz = 0;
    bool has_vram_clock = false;
    adlx_int vram_clock_mhz = 0;
    bool has_temperature = false;
    adlx_double temperature_c = 0;
    bool has_hotspot = false;
    adlx_double hotspot_c = 0;
    bool has_power = false;
    adlx_double power_w = 0;
    bool has_vram = false;
    adlx_int vram_mb = 0;
    bool has_total_board_power = false;
    adlx_double total_board_power_w = 0;
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
        << "  --target-pid <pid>    Exit cleanly when this Windows process exits\n"
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
        } else if (arg == "--target-pid") {
            const int parsed_pid = parse_int(require_value("--target-pid"), "--target-pid");
            if (parsed_pid <= 0) {
                usage_error("--target-pid must be > 0");
            }
            options.target_pid = static_cast<DWORD>(parsed_pid);
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
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
    return buffer;
}

std::string csv_escape(const std::string & value) {
    if (value.find_first_of(",\"\r\n") == std::string::npos) {
        return value;
    }
    std::string escaped = "\"";
    for (const char c : value) {
        if (c == '"') {
            escaped.push_back('"');
        }
        escaped.push_back(c);
    }
    escaped.push_back('"');
    return escaped;
}

std::string decimal_or_blank(bool has_value, adlx_double value) {
    if (!has_value) {
        return {};
    }
    std::ostringstream out;
    out << std::fixed << std::setprecision(3) << value;
    return out.str();
}

template <typename T>
std::string integer_or_blank(bool has_value, T value) {
    return has_value ? std::to_string(value) : std::string();
}

bool supported_result(ADLX_RESULT result, adlx_bool supported) {
    return ADLX_SUCCEEDED(result) && supported;
}

MetricSupport query_support(const IADLXGPUMetricsSupportPtr & support) {
    MetricSupport s;
    adlx_bool value = false;

    value = false;
    s.usage_result = support->IsSupportedGPUUsage(&value);
    s.usage = supported_result(s.usage_result, value);

    value = false;
    s.clock_result = support->IsSupportedGPUClockSpeed(&value);
    s.clock = supported_result(s.clock_result, value);

    value = false;
    s.vram_clock_result = support->IsSupportedGPUVRAMClockSpeed(&value);
    s.vram_clock = supported_result(s.vram_clock_result, value);

    value = false;
    s.temperature_result = support->IsSupportedGPUTemperature(&value);
    s.temperature = supported_result(s.temperature_result, value);

    value = false;
    s.hotspot_result = support->IsSupportedGPUHotspotTemperature(&value);
    s.hotspot = supported_result(s.hotspot_result, value);

    value = false;
    s.power_result = support->IsSupportedGPUPower(&value);
    s.power = supported_result(s.power_result, value);

    value = false;
    s.vram_result = support->IsSupportedGPUVRAM(&value);
    s.vram = supported_result(s.vram_result, value);

    value = false;
    s.total_board_power_result = support->IsSupportedGPUTotalBoardPower(&value);
    s.total_board_power = supported_result(s.total_board_power_result, value);

    return s;
}

void print_support(const MetricSupport & s) {
    std::cout
        << "Supported metrics:\n"
        << "  usage=" << s.usage
        << " result=" << static_cast<int>(s.usage_result) << "\n"
        << "  clock=" << s.clock
        << " result=" << static_cast<int>(s.clock_result) << "\n"
        << "  vram_clock=" << s.vram_clock
        << " result=" << static_cast<int>(s.vram_clock_result) << "\n"
        << "  temp=" << s.temperature
        << " result=" << static_cast<int>(s.temperature_result) << "\n"
        << "  hotspot=" << s.hotspot
        << " result=" << static_cast<int>(s.hotspot_result) << "\n"
        << "  power=" << s.power
        << " result=" << static_cast<int>(s.power_result) << "\n"
        << "  vram=" << s.vram
        << " result=" << static_cast<int>(s.vram_result) << "\n"
        << "  total_board_power=" << s.total_board_power
        << " result=" << static_cast<int>(s.total_board_power_result) << "\n";
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

    sample.has_adlx_timestamp = ADLX_SUCCEEDED(metrics->TimeStamp(&sample.adlx_timestamp_ms));
    if (support.usage) {
        sample.has_usage = ADLX_SUCCEEDED(metrics->GPUUsage(&sample.usage_pct));
    }
    if (support.clock) {
        sample.has_clock = ADLX_SUCCEEDED(metrics->GPUClockSpeed(&sample.clock_mhz));
    }
    if (support.vram_clock) {
        sample.has_vram_clock = ADLX_SUCCEEDED(metrics->GPUVRAMClockSpeed(&sample.vram_clock_mhz));
    }
    if (support.temperature) {
        sample.has_temperature = ADLX_SUCCEEDED(metrics->GPUTemperature(&sample.temperature_c));
    }
    if (support.hotspot) {
        sample.has_hotspot = ADLX_SUCCEEDED(metrics->GPUHotspotTemperature(&sample.hotspot_c));
    }
    if (support.power) {
        sample.has_power = ADLX_SUCCEEDED(metrics->GPUPower(&sample.power_w));
    }
    if (support.vram) {
        sample.has_vram = ADLX_SUCCEEDED(metrics->GPUVRAM(&sample.vram_mb));
    }
    if (support.total_board_power) {
        sample.has_total_board_power =
            ADLX_SUCCEEDED(metrics->GPUTotalBoardPower(&sample.total_board_power_w));
    }
    return sample;
}

int run_with_adlx(ADLXHelper & helper, const Options & options) {
    IADLXGPUListPtr gpus;
    ADLX_RESULT result = helper.GetSystemServices()->GetGPUs(&gpus);
    if (ADLX_FAILED(result) || !gpus || gpus->Empty()) {
        std::cerr << "ADLX GetGPUs failed or returned no GPUs. result="
                  << static_cast<int>(result) << "\n";
        return 3;
    }

    std::cout << "GPUs visible to ADLX: " << gpus->Size() << "\n";
    adlx_uint ordinal = 0;
    for (adlx_uint pos = gpus->Begin(); pos != gpus->End(); ++pos, ++ordinal) {
        IADLXGPUPtr current_gpu;
        const ADLX_RESULT gpu_result = gpus->At(pos, &current_gpu);
        if (ADLX_FAILED(gpu_result) || !current_gpu) {
            std::cout << "  [" << ordinal << "] <query failed> result="
                      << static_cast<int>(gpu_result) << "\n";
            continue;
        }
        const char * name = nullptr;
        const ADLX_RESULT name_result = current_gpu->Name(&name);
        std::cout << "  [" << ordinal << "] "
                  << ((ADLX_SUCCEEDED(name_result) && name) ? name : "<unknown>")
                  << "\n";
    }

    if (options.list_gpus) {
        return 0;
    }
    if (static_cast<adlx_uint>(options.gpu_index) >= gpus->Size()) {
        std::cerr << "Requested GPU index " << options.gpu_index
                  << " but ADLX reports " << gpus->Size() << " GPU(s).\n";
        return 4;
    }

    IADLXGPUPtr gpu;
    const adlx_uint gpu_pos = gpus->Begin() + static_cast<adlx_uint>(options.gpu_index);
    result = gpus->At(gpu_pos, &gpu);
    if (ADLX_FAILED(result) || !gpu) {
        std::cerr << "Failed to get GPU index " << options.gpu_index
                  << ". result=" << static_cast<int>(result) << "\n";
        return 5;
    }

    const char * raw_name = nullptr;
    const ADLX_RESULT name_result = gpu->Name(&raw_name);
    const std::string gpu_name =
        (ADLX_SUCCEEDED(name_result) && raw_name) ? raw_name : "<unknown>";

    IADLXPerformanceMonitoringServicesPtr perf;
    result = helper.GetSystemServices()->GetPerformanceMonitoringServices(&perf);
    if (ADLX_FAILED(result) || !perf) {
        std::cerr << "GetPerformanceMonitoringServices failed. result="
                  << static_cast<int>(result) << "\n";
        return 6;
    }

    IADLXGPUMetricsSupportPtr support_interface;
    result = perf->GetSupportedGPUMetrics(gpu, &support_interface);
    if (ADLX_FAILED(result) || !support_interface) {
        std::cerr << "GetSupportedGPUMetrics failed. result="
                  << static_cast<int>(result) << "\n";
        return 7;
    }

    const MetricSupport support = query_support(support_interface);
    print_support(support);

    DWORD session_id = 0;
    const BOOL got_session = ProcessIdToSessionId(GetCurrentProcessId(), &session_id);
    const bool remote_session = GetSystemMetrics(SM_REMOTESESSION) != 0;

    std::cout << "Selected GPU: [" << options.gpu_index << "] " << gpu_name << "\n";
    std::cout << "Windows session: id="
              << (got_session ? std::to_string(session_id) : std::string("unknown"))
              << " remote=" << (remote_session ? "yes" : "no") << "\n";
    std::cout << "Sampling: interval=" << options.interval_ms
              << " ms duration=" << options.duration_seconds
              << " s output=" << options.output.string();
    if (options.target_pid != 0) {
        std::cout << " target_pid=" << options.target_pid;
    }
    std::cout << "\n";

    const auto parent = options.output.parent_path();
    if (!parent.empty()) {
        std::error_code ec;
        std::filesystem::create_directories(parent, ec);
        if (ec) {
            std::cerr << "Failed to create output directory: "
                      << parent.string() << " error=" << ec.message() << "\n";
            return 8;
        }
    }

    std::ofstream csv(options.output, std::ios::out | std::ios::trunc);
    if (!csv) {
        std::cerr << "Failed to open output CSV: " << options.output.string() << "\n";
        return 9;
    }

    csv << "timestamp_local,elapsed_ms,adlx_timestamp_ms,windows_session_id,"
           "remote_session,gpu_index,gpu_name,gpu_usage_pct,gpu_clock_mhz,"
           "gpu_vram_clock_mhz,gpu_temp_c,gpu_hotspot_c,gpu_power_w,"
           "gpu_vram_mb,total_board_power_w,adlx_result\n";
    csv.flush();

    HANDLE target_process = nullptr;
    if (options.target_pid != 0) {
        target_process = OpenProcess(SYNCHRONIZE, FALSE, options.target_pid);
        if (!target_process) {
            std::cerr << "Failed to open target PID " << options.target_pid
                      << ". Win32 error=" << GetLastError() << "\n";
            return 10;
        }
    }

    const auto start = std::chrono::steady_clock::now();
    const long long duration_ms =
        static_cast<long long>(options.duration_seconds) * 1000LL;
    std::uint64_t sample_index = 0;

    while (!g_stop_requested.load()) {
        if (target_process) {
            const DWORD wait_result = WaitForSingleObject(target_process, 0);
            if (wait_result == WAIT_OBJECT_0) {
                std::cout << "Target PID " << options.target_pid
                          << " exited; stopping monitor.\n";
                break;
            }
            if (wait_result == WAIT_FAILED) {
                std::cerr << "WaitForSingleObject failed for target PID "
                          << options.target_pid << ". Win32 error=" << GetLastError() << "\n";
                break;
            }
        }
        const auto now = std::chrono::steady_clock::now();
        const long long elapsed_ms =
            std::chrono::duration_cast<std::chrono::milliseconds>(now - start).count();

        const Sample sample = read_sample(perf, gpu, support);

        csv << csv_escape(local_timestamp()) << ','
            << elapsed_ms << ','
            << integer_or_blank(sample.has_adlx_timestamp, sample.adlx_timestamp_ms) << ','
            << (got_session ? std::to_string(session_id) : std::string()) << ','
            << (remote_session ? 1 : 0) << ','
            << options.gpu_index << ','
            << csv_escape(gpu_name) << ','
            << decimal_or_blank(sample.has_usage, sample.usage_pct) << ','
            << integer_or_blank(sample.has_clock, sample.clock_mhz) << ','
            << integer_or_blank(sample.has_vram_clock, sample.vram_clock_mhz) << ','
            << decimal_or_blank(sample.has_temperature, sample.temperature_c) << ','
            << decimal_or_blank(sample.has_hotspot, sample.hotspot_c) << ','
            << decimal_or_blank(sample.has_power, sample.power_w) << ','
            << integer_or_blank(sample.has_vram, sample.vram_mb) << ','
            << decimal_or_blank(sample.has_total_board_power, sample.total_board_power_w) << ','
            << static_cast<int>(sample.result)
            << '\n';
        csv.flush();

        if (ADLX_FAILED(sample.result)) {
            std::cerr << "Sample " << sample_index
                      << " failed. ADLX result=" << static_cast<int>(sample.result) << "\n";
        }
        if (options.duration_seconds > 0 && elapsed_ms >= duration_ms) {
            break;
        }

        ++sample_index;
        const auto next_sample =
            start + std::chrono::milliseconds(
                        static_cast<long long>(sample_index) * options.interval_ms);
        std::this_thread::sleep_until(next_sample);
    }

    if (target_process) {
        CloseHandle(target_process);
    }

    std::cout << "Finished. CSV: " << options.output.string() << "\n";
    return 0;
}

} // namespace

int main(int argc, char ** argv) {
    try {
        const Options options = parse_options(argc, argv);
        SetConsoleCtrlHandler(console_handler, TRUE);

        ADLXHelper helper;
        const ADLX_RESULT init_result = helper.Initialize();
        if (ADLX_FAILED(init_result)) {
            std::cerr << "ADLX initialization failed. result="
                      << static_cast<int>(init_result) << "\n";
            return 2;
        }

        const char * version = helper.QueryVersion();
        std::cout << "ADLX runtime version: "
                  << (version ? version : "<unknown>") << "\n";

        const int run_result = run_with_adlx(helper, options);

        const ADLX_RESULT terminate_result = helper.Terminate();
        if (ADLX_FAILED(terminate_result)) {
            std::cerr << "ADLX termination failed. result="
                      << static_cast<int>(terminate_result) << "\n";
            return run_result == 0 ? 10 : run_result;
        }
        return run_result;
    } catch (const std::exception & ex) {
        std::cerr << "error: " << ex.what() << "\n";
        return 1;
    }
}
