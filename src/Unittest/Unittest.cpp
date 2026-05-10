#include "pch.h"
#include "Unittest/Unittest.h"

#if SWC_HAS_UNITTEST
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
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
            result.unittest             = false;
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

        void logUnittestStatus(const TaskContext& ctx, const char* name, bool ok)
        {
            const std::string header = std::format("Test-{}", name);
            Logger::printHeaderDot(ctx, LogColor::BrightCyan, header, ok ? LogColor::BrightGreen : LogColor::BrightRed, ok ? "ok" : "fail");
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
                if (CompilerInstance::dbgDevStop)
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
