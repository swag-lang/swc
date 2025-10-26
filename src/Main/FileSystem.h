#pragma once
SWC_BEGIN_NAMESPACE();

class Context;

namespace FileSystem
{
    Result resolveFile(const Context& ctx, fs::path& file);
    Result resolveFolder(const Context& ctx, fs::path& folder);
}

SWC_END_NAMESPACE();
