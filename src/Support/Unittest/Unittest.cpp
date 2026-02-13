#include "pch.h"
#include "Support/Unittest/Unittest.h"
#include "Main/CommandLine.h"
#include "Support/Os/Os.h"
#include "Support/Report/LogColor.h"
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
            const auto header = std::format("Test-{}", name);
            Logger::printHeaderDot(ctx,
                                   LogColor::BrightCyan,
                                   header,
                                   ok ? LogColor::BrightGreen : LogColor::BrightRed,
                                   ok ? "ok" : "fail");
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
            if (setupFn)
                setupFn(ctx);
        }

        for (const auto& test : testRegistry())
        {
            const Result result = test.fn(ctx);
            if (result == Result::Continue)
            {
                logUnittestStatus(ctx, test.name, true);
            }
            else
            {
                logUnittestStatus(ctx, test.name, false);
                if (CommandLine::dbgDevMode)
                    Os::panicBox("[DevMode] UNITTEST failed!");
                hasFailure = true;
            }
        }

        return hasFailure ? Result::Error : Result::Continue;
    }
}

#endif

SWC_END_NAMESPACE();
