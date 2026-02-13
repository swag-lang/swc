#include "pch.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    void setupBackendUnittests(TaskContext&)
    {
    }

    const Unittest::TestSetupRegistrar g_BackendUnittestSetup{&setupBackendUnittests};
}

#endif

SWC_END_NAMESPACE();
