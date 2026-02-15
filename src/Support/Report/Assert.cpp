#include "pch.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

void swcAssert(const char* expr, const char* file, int line)
{
    const Utf8 msg = std::format("assertion failed!\n\nFile: {}({})\nExpression: {}\n", file, line, expr);
    Os::panicBox(msg.c_str());
}

void swcInternalError(const char* file, int line)
{
    const Utf8 msg = std::format("internal error!\n\nFile: {}({})\n", file ? file : "<null>", line);
    Os::panicBox(msg.c_str());
}

SWC_END_NAMESPACE();
