#include "pch.h"
#include "Backend/MachineCode/CallConv.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if defined(SWC_HAS_UNITTEST) && SWC_HAS_UNITTEST

namespace
{
    Result setupBackendUnittests(TaskContext&)
    {
        CallConv::setup();
        return Result::Continue;
    }

    const Unittest::TestSetupRegistrar g_BackendUnittestSetup{&setupBackendUnittests};
}

#endif

SWC_END_NAMESPACE();
