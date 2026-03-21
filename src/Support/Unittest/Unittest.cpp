#include "pch.h"
#include "Support/Unittest/Unittest.h"
#if SWC_HAS_UNITTEST
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Support/Os/Os.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"
#include "Support/Report/ScopedTimedAction.h"
#endif

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
        TimedActionLog::ScopedStage stage(testCtx, {
            .key    = "verify",
            .label  = "Unittest",
            .verb   = "running backend checks",
            .detail = std::format("{} cases", testRegistry().size()),
        });
        Logger::ScopedStageMute muteNestedStages(testCtx.global().logger());

        bool       hasFailure      = false;
        const bool verboseUnittest = ctx.cmdLine().verboseUnittest;

        for (const SetupFn setupFn : setupRegistry())
        {
            if (setupFn)
                setupFn(testCtx);
        }

        for (const TestCase& test : testRegistry())
        {
            const Result result = test.fn(testCtx);
            if (result == Result::Continue)
            {
                if (verboseUnittest)
                    logUnittestStatus(testCtx, test.name, true);
            }
            else
            {
                logUnittestStatus(testCtx, test.name, false);
                if (CompilerInstance::dbgDevMode)
                    Os::panicBox("[DevMode] UNITTEST failed!");
                hasFailure = true;
                stage.markFailure();
            }
        }

        return hasFailure ? Result::Error : Result::Continue;
    }
}

#endif

SWC_END_NAMESPACE();
