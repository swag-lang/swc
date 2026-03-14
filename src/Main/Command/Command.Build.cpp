#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Support/Report/ScopedTimedAction.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool hasNewErrors(const uint64_t errorsBefore)
    {
        return Stats::get().numErrors.load(std::memory_order_relaxed) != errorsBefore;
    }

    bool finishAction(ScopedTimedAction& action, const uint64_t errorsBefore)
    {
        if (hasNewErrors(errorsBefore))
        {
            action.fail();
            return false;
        }

        action.success();
        return true;
    }

    bool runNativeBackend(CompilerInstance& compiler, const Runtime::BuildCfgBackendKind backendKind, const bool runArtifact)
    {
        compiler.buildCfg().backendKind = backendKind;

        NativeBackendBuilder builder(compiler, runArtifact);
        if (builder.run() != Result::Continue)
            return false;

        return Stats::get().numErrors.load(std::memory_order_relaxed) == 0;
    }

    void runNativeCommand(CompilerInstance& compiler, const bool runArtifact)
    {
        const TaskContext ctx(compiler);
        ScopedTimedAction analyzeAction(ctx, "Analyze", "sources");
        const uint64_t    errorsBefore = Stats::get().numErrors.load(std::memory_order_relaxed);
        Command::sema(compiler);
        if (!finishAction(analyzeAction, errorsBefore))
            return;

        const Runtime::BuildCfgBackendKind backendKind = compiler.buildCfg().backendKind;
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
