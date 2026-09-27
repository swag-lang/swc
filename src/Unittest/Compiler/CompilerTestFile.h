#pragma once
#include "Main/FileSystem.h"

SWC_BEGIN_NAMESPACE();

namespace CompilerTestFile
{
    inline Result writeText(const fs::path& path, std::string_view text)
    {
        std::error_code ec;
        fs::create_directories(path.parent_path(), ec);
        if (ec)
            return Result::Error;

        FileSystem::IoErrorInfo error;
        return FileSystem::writeBinaryFile(path, text.data(), text.size(), error);
    }

    inline Result readText(std::string& result, const fs::path& path)
    {
        FileSystem::IoErrorInfo error;
        return FileSystem::readTextFile(path, result, error);
    }
}

SWC_END_NAMESPACE();
