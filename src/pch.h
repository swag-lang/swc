#pragma once
// ReSharper disable CppInconsistentNaming

#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <variant>
#include <vector>
#include <tuple>
#include <cstdint>
#include <mutex>
#include <vector>
#include <cassert>
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>
#include <array>

namespace fs = std::filesystem; 

#define SWAG_HAS_ASSERT 1

#include "Report/Check.h"
#include "Core/Utf8.h"
