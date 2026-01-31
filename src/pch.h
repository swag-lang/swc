// ReSharper disable CppClangTidyModernizeMacroToEnum
#pragma once

#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <format>
#include <fstream>
#include <functional>
#include <iostream>
#include <map>
#include <memory>
#include <mutex>
#include <print>
#include <ranges>
#include <regex>
#include <set>
#include <shared_mutex>
#include <span>
#include <string>
#include <thread>
#include <tuple>
#include <unordered_map>
#include <unordered_set>
#include <variant>
#include <vector>

// ReSharper disable CppInconsistentNaming
namespace fs = std::filesystem;

// clang-format off
#define SWC_BEGIN_NAMESPACE(); namespace swc {
#define SWC_END_NAMESPACE(); }
// clang-format on

#ifdef SWC_DEV_MODE
#define SWC_FORCE_STATS
#define SWC_HAS_ASSERT           1
#define SWC_HAS_RACE_CONDITION   1
#define SWC_HAS_REF_DEBUG_INFO   1
#define SWC_HAS_VISIT_DEBUG_INFO 1
#define SWC_HAS_SEMA_DEBUG_INFO  1
#define SWC_HAS_TOKEN_DEBUG_INFO 1
#else
#define SWC_HAS_ASSERT           0
#define SWC_HAS_RACE_CONDITION   0
#define SWC_HAS_REF_DEBUG_INFO   0
#define SWC_HAS_VISIT_DEBUG_INFO 0
#define SWC_HAS_SEMA_DEBUG_INFO  0
#define SWC_HAS_TOKEN_DEBUG_INFO 0
#endif

#ifdef SWC_FORCE_STATS
#define SWC_HAS_STATS 1
#else
#define SWC_HAS_STATS 0
#endif

#include "Core/Flags.h"
#include "Core/Result.h"
#include "Core/StrongRef.h"
#include "Core/Utf8.h"
#include "Report/Assert.h"
