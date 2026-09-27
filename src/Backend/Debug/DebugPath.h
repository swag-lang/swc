#pragma once
#include "Support/Core/Utf8.h"

#include <filesystem>

SWC_BEGIN_NAMESPACE();

namespace DebugPath
{
    // Normalises a source path the way debuggers expect it in CodeView line tables.
    inline Utf8 normalizedString(const std::filesystem::path& path)
    {
        std::filesystem::path normalized = path.lexically_normal();
        normalized.make_preferred();
        return {normalized.string()};
    }
}

SWC_END_NAMESPACE();
