#include "pch.h"
#include "Main/TaskContext.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

void swcAssert(const char* expr, const char* file, int line)
{
    std::println(stderr, "assertion failed {} ({}:{})", expr ? expr : "<null>", file ? file : "<null>", line);
    (void) std::fflush(stderr);

    Os::assertBox(expr, file, line);
}

[[noreturn]] void swcInternalError(const TaskContext& ctx, const char* file, int line)
{
    (void) ctx;
    std::println(stderr, "internal error ({}:{})", file ? file : "<null>", line);
    (void) std::fflush(stderr);

    std::abort();
}

SWC_END_NAMESPACE();
