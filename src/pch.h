#pragma once
// ReSharper disable CppInconsistentNaming

#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <mutex>
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

namespace fs = std::filesystem;

// clang-format off
#define SWC_BEGIN_NAMESPACE() namespace swc {
#define SWC_END_NAMESPACE() }
// clang-format on

#define SWC_HAS_ASSERT 1
#define SWC_HAS_STATS  1

#include "Core/Flags.h"
#include "Core/SmallVector.h"
#include "Core/Utf8.h"
#include "Report/Check.h"
