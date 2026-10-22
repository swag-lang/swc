#pragma once
#include "Support/Core/Utf8.h"

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

    // The file name of a build's primary source, as its build-info record names it.
    inline Utf8 buildInfoFileName(const Utf8& sourcePath)
    {
        if (sourcePath.empty())
            return {};
        return {std::filesystem::path(sourcePath.c_str()).filename().string()};
    }
}

SWC_END_NAMESPACE();
