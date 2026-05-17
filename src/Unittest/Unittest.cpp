#include "pch.h"
#include "Unittest/Unittest.h"

#if SWC_HAS_UNITTEST
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
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
        struct TimedTestResult
        {
            const char* name       = nullptr;
            uint64_t    durationNs = 0;
        };

        bool shouldRunTest(const CommandLine& cmdLine, const TestCase& test)
        {
            if (test.kind == TestKind::Filesystem && !cmdLine.devFull)
                return false;

            return true;
        }

        CommandLine makeIsolatedUnittestCommandLine(const CommandLine& cmdLine)
        {
            CommandLine result = cmdLine;
            result.command     = CommandKind::Syntax;
            result.name.clear();
            result.moduleNamespace.clear();
            result.moduleNamespaceStorage.clear();
            result.fileFilter.clear();
            result.tags.clear();
            result.directories.clear();
            result.files.clear();
            result.importApiModules.clear();
            result.importApiDirs.clear();
            result.importApiFiles.clear();
            result.configFile.clear();
            result.modulePath.clear();
            result.exportApiDir.clear();
            result.outDir.clear();
            result.workDir.clear();
            result.outDirStorage.clear();
            result.workDirStorage.clear();
            result.clear                = false;
            result.dryRun               = false;
            result.showConfig           = false;
            result.sourceDrivenTest     = false;
            result.artifactKindExplicit = false;
            result.commandExplicit      = false;
            result.verboseUnittest      = false;
            return result;
        }

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

        Utf8 formatDuration(uint64_t durationNs)
        {
            return Utf8Helper::toNiceTime(Timer::toSeconds(durationNs));
        }

        Utf8 formatUnittestStatus(bool ok, uint64_t durationNs)
        {
            return std::format("{} ({})", ok ? "ok" : "fail", formatDuration(durationNs));
        }

        void logUnittestStatus(const TaskContext& ctx, const char* name, bool ok, uint64_t durationNs)
        {
            const std::string header = std::format("Test-{}", name);
            const Utf8        status = formatUnittestStatus(ok, durationNs);
            Logger::printHeaderDot(ctx, LogColor::BrightCyan, header, ok ? LogColor::BrightGreen : LogColor::BrightRed, status);
        }

        bool hasLongerDuration(const TimedTestResult& lhs, const TimedTestResult& rhs)
        {
            return lhs.durationNs > rhs.durationNs;
        }

        uint64_t totalTestDuration(const std::vector<TimedTestResult>& timedTests)
        {
            uint64_t result = 0;
            for (const TimedTestResult& timedTest : timedTests)
                result += timedTest.durationNs;
            return result;
        }

        void logUnittestSummary(const TaskContext& ctx, const std::vector<TimedTestResult>& timedTests, uint64_t setupDurationNs, size_t skippedFilesystemTests)
        {
            const uint64_t totalTestDurationNs = totalTestDuration(timedTests);
            const Utf8     testsSummary        = std::format("{} tests ({})", Utf8Helper::toNiceBigNumber(timedTests.size()), formatDuration(totalTestDurationNs));
            Logger::printHeaderDot(ctx, LogColor::BrightCyan, "Tests", LogColor::White, testsSummary);

            if (setupDurationNs)
                Logger::printHeaderDot(ctx, LogColor::BrightCyan, "Setup", LogColor::White, formatDuration(setupDurationNs));

            if (skippedFilesystemTests)
            {
                const Utf8 skippedSummary = std::format("{} filesystem tests (run with --dev-full)", Utf8Helper::toNiceBigNumber(skippedFilesystemTests));
                Logger::printHeaderDot(ctx, LogColor::BrightCyan, "Skipped", LogColor::White, skippedSummary);
            }

            std::vector<TimedTestResult> slowTests = timedTests;
            std::ranges::sort(slowTests, hasLongerDuration);
            const size_t count = std::min<size_t>(10, slowTests.size());
            for (size_t i = 0; i < count; ++i)
            {
                const TimedTestResult& slowTest = slowTests[i];
                const std::string      header   = std::format("Slow-{:02}", i + 1);
                const Utf8             message  = std::format("{} ({})", slowTest.name, formatDuration(slowTest.durationNs));
                Logger::printHeaderDot(ctx, LogColor::BrightCyan, header, LogColor::White, message);
            }
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
        // Internal C++ unit tests must stay isolated from the caller inputs so they
        // cannot accidentally recollect the user sources before the real command runs.
        CompilerInstance compiler(ctx.global(), makeIsolatedUnittestCommandLine(ctx.cmdLine()));
        TaskContext      testCtx(compiler);
        if (compiler.setupSema(testCtx) != Result::Continue)
            return Result::Error;
        TimedActionLog::ScopedStage stage(testCtx, TimedActionLog::Stage::Unittest);
        Logger::ScopedStageMute     muteNestedStages(testCtx.global().logger());

        bool                         hasFailure             = false;
        uint64_t                     setupDurationNs        = 0;
        size_t                       skippedFilesystemTests = 0;
        std::vector<TimedTestResult> timedTests;
        const bool                   verboseUnittest = ctx.cmdLine().verboseUnittest;
        timedTests.reserve(testRegistry().size());

        for (const SetupFn setupFn : setupRegistry())
        {
            if (setupFn)
            {
                const Timer::Tick startTick = Timer::Clock::now();
                setupFn(testCtx);
                setupDurationNs += std::chrono::duration_cast<std::chrono::nanoseconds>(Timer::Clock::now() - startTick).count();
            }
        }

        for (const TestCase& test : testRegistry())
        {
            if (!shouldRunTest(ctx.cmdLine(), test))
            {
                if (test.kind == TestKind::Filesystem)
                    ++skippedFilesystemTests;
                continue;
            }

            const Timer::Tick startTick  = Timer::Clock::now();
            const Result      result     = test.fn(testCtx);
            const uint64_t    durationNs = std::chrono::duration_cast<std::chrono::nanoseconds>(Timer::Clock::now() - startTick).count();
            const bool        ok         = result == Result::Continue;

            timedTests.push_back({test.name, durationNs});
            if (ok)
            {
                if (verboseUnittest)
                    logUnittestStatus(testCtx, test.name, true, durationNs);
            }
            else
            {
                logUnittestStatus(testCtx, test.name, false, durationNs);
                if (CompilerInstance::dbgDevStop)
                    Os::panicBox("[DevMode] UNITTEST failed!");
                hasFailure = true;
                stage.markFailure();
            }
        }

        if (verboseUnittest)
            logUnittestSummary(testCtx, timedTests, setupDurationNs, skippedFilesystemTests);

        return hasFailure ? Result::Error : Result::Continue;
    }
}

#endif

SWC_END_NAMESPACE();
