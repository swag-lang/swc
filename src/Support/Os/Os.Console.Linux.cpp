#include "pch.h"
#include "Support/Os/Os.h"
#include "Main/ExitCodes.h"

#ifdef __linux__

SWC_BEGIN_NAMESPACE();

void Os::initialize()
{
}

void Os::panicBox(const std::string_view expr)
{
    std::println(stderr, "panic: {}", expr.empty() ? "<null>" : expr);
    Os::exit(ExitCode::PanicBox);
}

SWC_END_NAMESPACE();
#endif
