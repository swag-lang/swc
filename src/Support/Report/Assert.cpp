#include "pch.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

void swcAssert(const char* expr, const char* file, int line)
{
    std::println(stderr, "assertion failed {} ({}:{})", expr ? expr : "<null>", file ? file : "<null>", line);
    (void) std::fflush(stderr);

    Os::assertBox(expr, file, line);
}

[[noreturn]] void swcInternalError(const char* file, int line)
{
    std::println(stderr, "internal error ({}:{})", file ? file : "<null>", line);
    (void) std::fflush(stderr);

    std::abort();
}

SWC_END_NAMESPACE();
