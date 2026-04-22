#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Support/Report/ScopedTimedAction.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool hasErrors(const uint64_t errorsBefore)
    {
        return Stats::getNumErrors() != errorsBefore;
    }

    template<typename FUNC>
    Result runAfterPauses(TaskContext& ctx, const FUNC& func)
    {
        while (true)
        {
            const Result result = func();
            if (result != Result::Pause)
                return result;

            Sema::waitDone(ctx, ctx.compiler().jobClientId());
            if (Stats::hasError())
                return Result::Error;
        }
    }

    bool runNativeBackend(CompilerInstance& compiler, const Runtime::BuildCfgBackendKind backendKind, const bool runArtifact)
    {
        compiler.buildCfg().backendKind = backendKind;
        TaskContext ctx(compiler);

        NativeBackendBuilder builder(compiler, runArtifact);
        if (runAfterPauses(ctx, [&] {
                return builder.run();
            }) != Result::Continue)
            return false;

        return !Stats::hasError();
    }

    void runNativeCommand(CompilerInstance& compiler, const bool runArtifact)
    {
        const TaskContext ctx(compiler);
        TimedActionLog::printBuildConfiguration(ctx);
        const uint64_t errorsBefore = Stats::getNumErrors();
        Command::sema(compiler);
        if (hasErrors(errorsBefore))
            return;

        const Runtime::BuildCfgBackendKind backendKind = effectiveBackendKind(compiler.cmdLine(), compiler.buildCfg().backendKind);
        runNativeBackend(compiler, backendKind, runArtifact && backendKind == Runtime::BuildCfgBackendKind::Executable);
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
