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
            const auto header = std::format("[Test-{}]", name);
            Logger::printHeaderCentered(ctx,
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
            if (!setupFn || setupFn(ctx) != Result::Continue)
            {
                Logger::printHeaderCentered(ctx, LogColor::BrightCyan, "[unittest setup]", LogColor::BrightRed, "fail");
                return Result::Error;
            }
        }

        for (const auto& test : testRegistry())
        {
            if (!test.name || !test.fn)
            {
                Logger::printHeaderCentered(ctx, LogColor::BrightCyan, "[unittest <invalid>]", LogColor::BrightRed, "fail");
                hasFailure = true;
                continue;
            }

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
