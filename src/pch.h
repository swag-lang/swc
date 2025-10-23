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
#include <string>
#include <thread>
#include <tuple>
#include <unordered_map>
#include <variant>
#include <vector>

namespace fs = std::filesystem;

#define SWC_HAS_ASSERT 1
#define SWC_HAS_STATS  1

#include "Core/Flags.h"
#include "Core/Utf8.h"
#include "Report/Check.h"
