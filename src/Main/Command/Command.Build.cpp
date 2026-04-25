#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/Command/CommandRun.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Support/Report/ScopedTimedAction.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void runNativeCommand(CompilerInstance& compiler, const bool runArtifact)
    {
        const TaskContext ctx(compiler);
        TimedActionLog::printBuildConfiguration(ctx);
        const uint64_t errorsBefore = Stats::getNumErrors();
        Command::sema(compiler);
        if (Stats::getNumErrors() != errorsBefore)
            return;

        const Runtime::BuildCfgBackendKind backendKind = effectiveBackendKind(compiler.cmdLine(), compiler.buildCfg().backendKind);
        compiler.buildCfg().backendKind = backendKind;

        TaskContext          nativeCtx(compiler);
        NativeBackendBuilder builder(compiler, runArtifact && backendKind == Runtime::BuildCfgBackendKind::Executable);
        if (CommandRun::afterPauses(nativeCtx, [&] {
                return builder.run();
            }) != Result::Continue)
            return;

        if (Stats::hasError())
            return;
    }
}

namespace Command
{
    void build(CompilerInstance& compiler)
    {
        runNativeCommand(compiler, false);
    }

    void run(CompilerInstance& compiler)
    {
        runNativeCommand(compiler, true);
    }
}

SWC_END_NAMESPACE();
