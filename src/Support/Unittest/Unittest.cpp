#include "pch.h"
#include "Support/Report/LogColor.h"
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

        void logUnittestStatus(const TaskContext& ctx, const char* name, bool ok)
        {
            Logger::print(ctx, std::format("[unittest] {} ", name));
            Logger::print(ctx, LogColorHelper::toAnsi(ctx, ok ? LogColor::BrightGreen : LogColor::BrightRed));
            Logger::print(ctx, ok ? "ok" : "fail");
            Logger::print(ctx, LogColorHelper::toAnsi(ctx, LogColor::Reset));
            Logger::print(ctx, "\n");
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
            SWC_ASSERT(test.name && test.fn);

            const Result result = test.fn(ctx);
            if (result == Result::Continue)
            {
                logUnittestStatus(ctx, test.name, true);
            }
            else
            {
                logUnittestStatus(ctx, test.name, false);
                hasFailure = true;
            }
        }

        return hasFailure ? Result::Error : Result::Continue;
    }
}

#endif

SWC_END_NAMESPACE();
