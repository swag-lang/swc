#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/Command/CommandRun.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Support/Report/ScopedTimedAction.h"

SWC_BEGIN_NAMESPACE();

namespace Command
{
    namespace
    {
        Result finishNonArtifactBackend(CompilerInstance& compiler)
        {
            TaskContext outputCtx(compiler);
            return CommandRun::afterPauses(outputCtx, [&] {
                return compiler.ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassBeforeOutput);
            });
        }

        Result finishBuildBackend(CompilerInstance& compiler, const bool runArtifact)
        {
            const Runtime::BuildCfgBackendKind backendKind = effectiveBackendKind(compiler.cmdLine(), compiler.buildCfg().backendKind);
            compiler.buildCfg().backendKind                = backendKind;

            if (!Runtime::backendKindProducesNativeArtifact(backendKind))
                return finishNonArtifactBackend(compiler);

            TaskContext          nativeCtx(compiler);
            NativeBackendBuilder builder(compiler, runArtifact && backendKind == Runtime::BuildCfgBackendKind::Executable);
            return CommandRun::afterPauses(nativeCtx, [&] {
                return builder.run();
            });
        }
    }

    void build(CompilerInstance& compiler)
    {
        const TaskContext ctx(compiler);
        TimedActionLog::printBuildConfiguration(ctx);
        const uint64_t errorsBefore = Stats::getNumErrors();
        sema(compiler);
        if (Stats::getNumErrors() != errorsBefore)
            return;

        if (finishBuildBackend(compiler, false) != Result::Continue)
            return;
    }

    void run(CompilerInstance& compiler)
    {
        const TaskContext ctx(compiler);
        TimedActionLog::printBuildConfiguration(ctx);
        const uint64_t errorsBefore = Stats::getNumErrors();
        sema(compiler);
        if (Stats::getNumErrors() != errorsBefore)
            return;

        if (finishBuildBackend(compiler, true) != Result::Continue)
            return;
    }
}

SWC_END_NAMESPACE();
