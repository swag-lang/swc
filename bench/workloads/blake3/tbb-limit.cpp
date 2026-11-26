#include <oneapi/tbb/global_control.h>
#include <oneapi/tbb/version.h>

extern "C" void set_tbb_threads(unsigned int count)
{
    static const oneapi::tbb::global_control control(oneapi::tbb::global_control::max_allowed_parallelism, count);
}

extern "C" const char *tbb_version()
{
    return TBB_runtime_version();
}
