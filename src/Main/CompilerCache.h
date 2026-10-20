#pragma once
#include "Main/Version.h"
#include "Support/Core/Utf8.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

inline const Utf8& compilerCacheIdentity()
{
    static const Utf8 identity = []() -> Utf8 {
        const fs::path  exe = Os::getExeFullName();
        std::error_code ec;
        const auto      size = fs::file_size(exe, ec);
        if (ec)
            return {};
        const auto time = fs::last_write_time(exe, ec);
        if (ec)
            return {};
        return std::format("{}:{}:{}:{}.{}.{}", exe.generic_string(), size, time.time_since_epoch().count(), SWC_VERSION, SWC_REVISION, SWC_BUILD_NUM);
    }();
    return identity;
}

SWC_END_NAMESPACE();
