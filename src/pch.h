#pragma once
// ReSharper disable CppInconsistentNaming

#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <variant>
#include <vector>

namespace fs = std::filesystem; 

#define SWAG_HAS_ASSERT 1

#include "Report/Check.h"
