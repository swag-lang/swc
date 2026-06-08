#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/Command/CommandRun.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE();

namespace Command
{
    namespace
    {
        Result finishNonArtifactBackend(CompilerInstance& compiler)
        {
            TaskContext outputCtx(compiler);
            return CommandRun::afterPauses(outputCtx, [&] { return compiler.ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassBeforeOutput); });
        }

        Result finishBuildBackend(CompilerInstance& compiler, const bool runArtifact)
        {
            const Runtime::BuildCfgBackendKind backendKind = effectiveBackendKind(compiler.cmdLine(), compiler.buildCfg().backendKind);
            compiler.buildCfg().backendKind                = backendKind;

            if (!Runtime::backendKindProducesNativeArtifact(backendKind))
                return finishNonArtifactBackend(compiler);

            const bool runExecutable = runArtifact && backendKind == Runtime::BuildCfgBackendKind::Executable;

            // Workspace pipeline: build everything but the link, then hand the prepared builder back so
            // the caller can run the external linker off the main thread and finish it at a later sync
            // point. The builder owns its own TaskContext, so it only needs the compiler kept alive.
            if (compiler.deferNativeLink())
            {
                auto builder = std::make_unique<NativeBackendBuilder>(compiler, runExecutable);
                if (CommandRun::afterPauses(builder->ctx(), [&] { return builder->prepareForLink(); }) != Result::Continue)
                    return Result::Error;

                compiler.setDeferredBuilder(std::move(builder));
                return Result::Continue;
            }

            TaskContext          nativeCtx(compiler);
            NativeBackendBuilder builder(compiler, runExecutable);
            return CommandRun::afterPauses(nativeCtx, [&] { return builder.run(); });
        }
    }

    void build(CompilerInstance& compiler)
    {
        const uint64_t errorsBefore = Stats::getNumErrors();
        sema(compiler);
        if (Stats::getNumErrors() != errorsBefore)
            return;

        if (finishBuildBackend(compiler, false) != Result::Continue)
            return;
    }

    void run(CompilerInstance& compiler)
    {
        const uint64_t errorsBefore = Stats::getNumErrors();
        sema(compiler);
        if (Stats::getNumErrors() != errorsBefore)
            return;

        if (finishBuildBackend(compiler, true) != Result::Continue)
            return;
    }
}

SWC_END_NAMESPACE();
