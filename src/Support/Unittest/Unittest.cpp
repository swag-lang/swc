#include "pch.h"
#include "Support/Unittest/Unittest.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

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

    Result runAll(TaskContext& ctx)
    {
        bool hasFailure = false;

        for (const auto setupFn : setupRegistry())
        {
            if (!setupFn || setupFn(ctx) != Result::Continue)
            {
                Logger::print(ctx, "[unittest] setup fail\n");
                return Result::Error;
            }
        }

        for (const auto& test : testRegistry())
        {
            if (!test.name || !test.fn)
            {
                Logger::print(ctx, "[unittest] <invalid> fail\n");
                hasFailure = true;
                continue;
            }

            const auto result = test.fn(ctx);
            if (result == Result::Continue)
            {
                Logger::print(ctx, std::format("[unittest] {} ok\n", test.name));
            }
            else
            {
                Logger::print(ctx, std::format("[unittest] {} fail\n", test.name));
                hasFailure = true;
            }
        }

        return hasFailure ? Result::Error : Result::Continue;
    }
}

#endif

SWC_END_NAMESPACE();
