#include "pch.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

void swcAssert(const char* expr, const char* file, int line)
{
    std::println(stderr, "Assertion failed: {} ({}:{})", expr ? expr : "<null>", file ? file : "<null>", line);
    (void) std::fflush(stderr);

    Os::assertBox(expr, file, line);
}

[[noreturn]] void swcInternalError(const char* file, int line)
{
    std::string msg = "internal error (";
    msg += file;
    msg += ":";
    msg += std::to_string(line);
    msg += ")\n";
    std::fwrite(msg.data(), sizeof(char), msg.size(), stderr);
    std::fflush(stderr);

    msg.pop_back();
    Os::panicBox(msg.c_str());
    std::abort();
}

SWC_END_NAMESPACE();
