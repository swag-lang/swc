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
    void build(CompilerInstance& compiler)
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
        NativeBackendBuilder builder(compiler, false);
        if (CommandRun::afterPauses(nativeCtx, [&] {
                return builder.run();
            }) != Result::Continue)
            return;
    }

    void run(CompilerInstance& compiler)
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
        NativeBackendBuilder builder(compiler, backendKind == Runtime::BuildCfgBackendKind::Executable);
        if (CommandRun::afterPauses(nativeCtx, [&] {
                return builder.run();
            }) != Result::Continue)
            return;
    }
}

SWC_END_NAMESPACE();
