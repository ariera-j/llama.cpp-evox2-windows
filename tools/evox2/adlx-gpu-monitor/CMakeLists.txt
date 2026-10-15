cmake_minimum_required(VERSION 3.20)

project(evox2_adlx_gpu_monitor LANGUAGES CXX)

if(NOT WIN32)
    message(FATAL_ERROR "evox2-adlx-gpu-monitor is Windows-only.")
endif()

if(NOT DEFINED ADLX_ROOT OR ADLX_ROOT STREQUAL "")
    message(FATAL_ERROR "Set ADLX_ROOT to an AMD ADLX SDK checkout (v2.0 is the pinned/tested target).")
endif()

get_filename_component(ADLX_ROOT "${ADLX_ROOT}" ABSOLUTE)

set(ADLX_HELPER_CPP "${ADLX_ROOT}/SDK/ADLXHelper/Windows/Cpp/ADLXHelper.cpp")
set(ADLX_WIN_APIS_CPP "${ADLX_ROOT}/SDK/platform/Windows/WinAPIs.cpp")
set(ADLX_PERF_HEADER "${ADLX_ROOT}/SDK/Include/IPerformanceMonitoring.h")

foreach(required_file IN ITEMS "${ADLX_HELPER_CPP}" "${ADLX_WIN_APIS_CPP}" "${ADLX_PERF_HEADER}")
    if(NOT EXISTS "${required_file}")
        message(FATAL_ERROR "Required ADLX SDK file not found: ${required_file}")
    endif()
endforeach()

add_executable(evox2-adlx-gpu-monitor
    src/adlx_gpu_monitor.cpp
    "${ADLX_HELPER_CPP}"
    "${ADLX_WIN_APIS_CPP}"
)

target_include_directories(evox2-adlx-gpu-monitor PRIVATE "${ADLX_ROOT}")
target_compile_features(evox2-adlx-gpu-monitor PRIVATE cxx_std_17)

if(MSVC)
    target_compile_options(evox2-adlx-gpu-monitor PRIVATE /W4 /EHsc /utf-8)
endif()

set_target_properties(evox2-adlx-gpu-monitor PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_BINARY_DIR}/bin"
)
