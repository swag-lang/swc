// Link only into the CPU-rejection fixture, with --wrap=__cpu_indicator_init. Leaving GCC's
// detector uninitialized simulates an unsupported CPU without executing unsupported code.
#include <unistd.h>

extern "C" int __wrap___cpu_indicator_init()
{
    return 0;
}

namespace
{
    struct MustNotInitialize
    {
        MustNotInitialize() { _exit(98); }
    } mustNotInitialize;
}

int main()
{
    return 99;
}
