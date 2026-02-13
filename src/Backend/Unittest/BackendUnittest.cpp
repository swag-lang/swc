#include "pch.h"
#include "Backend/Unittest/BackendUnittest.h"
#include "Backend/MachineCode/CallConv.h"

SWC_BEGIN_NAMESPACE();

#if SWC_DEV_MODE

namespace Backend::Unittest
{
    namespace
    {
        std::vector<BackendTestCase>& registry()
        {
            static std::vector<BackendTestCase> allTests;
            return allTests;
        }
    }

    void registerTest(BackendTestCase test)
    {
        registry().push_back(test);
    }

    void runAll(TaskContext& ctx)
    {
        CallConv::setup();
        for (const auto& test : registry())
        {
            SWC_ASSERT(test.name);
            SWC_ASSERT(test.fn);
            test.fn(ctx);
        }
    }
}

#endif

SWC_END_NAMESPACE();
