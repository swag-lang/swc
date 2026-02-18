#include "pch.h"
#include "Support/Unittest/Unittest.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
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
            const std::string header = std::format("Test-{}", name);
            Logger::printHeaderDot(ctx,
                                   LogColor::BrightCyan,
                                   header,
                                   ok ? LogColor::BrightGreen : LogColor::BrightRed,
                                   ok ? "ok" : "fail");
        }

        void logUnittestSummary(const TaskContext& ctx, uint32_t total, uint32_t failures)
        {
            Logger::printHeaderDot(ctx,
                                   LogColor::BrightCyan,
                                   "Internal-Unittest",
                                   failures ? LogColor::BrightRed : LogColor::BrightGreen,
                                   std::format("{} passed / {} failed / {} total", total - failures, failures, total));
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

    Result runAll(const TaskContext& ctx)
    {
        CompilerInstance compiler(ctx.global(), ctx.cmdLine());
        TaskContext      testCtx(compiler);
        compiler.setupSema(testCtx);

        bool       hasFailure      = false;
        uint32_t   totalTests      = 0;
        uint32_t   numFailedTests  = 0;
        const bool verboseUnittest = ctx.cmdLine().verboseInternalUnittest;

        for (const SetupFn setupFn : setupRegistry())
        {
            if (setupFn)
                setupFn(testCtx);
        }

        for (const TestCase& test : testRegistry())
        {
            totalTests++;
            const Result result = test.fn(testCtx);
            if (result == Result::Continue)
            {
                if (verboseUnittest)
                    logUnittestStatus(testCtx, test.name, true);
            }
            else
            {
                logUnittestStatus(testCtx, test.name, false);
                if (CommandLine::dbgDevMode)
                    Os::panicBox("[DevMode] UNITTEST failed!");
                hasFailure = true;
                numFailedTests++;
            }
        }

        if (verboseUnittest)
            logUnittestSummary(testCtx, totalTests, numFailedTests);

        return hasFailure ? Result::Error : Result::Continue;
    }
}

#endif

SWC_END_NAMESPACE();
