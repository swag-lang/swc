#include "pch.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

void swcAssert(const char* expr, const char* file, int line)
{
    const Utf8 fileLoc = FileSystem::formatFileLocation(nullptr, fs::path(file ? file : "<null>"), static_cast<uint32_t>(line));
    const Utf8 msg     = std::format("assertion failed!\n\nFile: {}\nExpression: {}\n", fileLoc, expr);
    Os::panicBox(msg.c_str());
}

void swcInternalError(const char* file, int line, const char* expr)
{
    const Utf8 fileLoc = FileSystem::formatFileLocation(nullptr, fs::path(file ? file : "<null>"), static_cast<uint32_t>(line));
    Utf8       msg     = std::format("internal error!\n\nFile: {}\n", fileLoc);
    if (expr)
        msg += std::format("Expression: {}\n", expr);
    Os::panicBox(msg.c_str());
}

SWC_END_NAMESPACE();
