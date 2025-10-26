#pragma once
SWC_BEGIN_NAMESPACE();

class Context;

namespace FileSystem
{
    Result resolveFile(const Context& ctx, fs::path& file);
    Result resolveFolder(const Context& ctx, fs::path& folder);
    Utf8   normalizeSystemMessage(const Utf8& msg);
    Utf8   normalizeSystemMessage(std::error_code ec);
}

SWC_END_NAMESPACE();
