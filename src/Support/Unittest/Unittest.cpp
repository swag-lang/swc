#include "pch.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_DEV_MODE

namespace Unittest
{
    namespace
    {
        std::vector<TestCase>& testRegistry()
        {
            static std::vector<TestCase> allTests;
            return allTests;
        }

        std::vector<SetupFn>& setupRegistry()
        {
            static std::vector<SetupFn> allSetups;
            return allSetups;
        }
    }

    void registerTest(TestCase test)
    {
        testRegistry().push_back(test);
    }

    void registerSetup(SetupFn setupFn)
    {
        setupRegistry().push_back(setupFn);
    }

    void runAll(TaskContext& ctx)
    {
        for (const auto setupFn : setupRegistry())
        {
            SWC_ASSERT(setupFn);
            setupFn(ctx);
        }

        for (const auto& test : testRegistry())
        {
            SWC_ASSERT(test.name);
            SWC_ASSERT(test.fn);
            test.fn(ctx);
        }
    }
}

#endif

SWC_END_NAMESPACE();
