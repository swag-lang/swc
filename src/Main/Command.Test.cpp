#include "pch.h"
#include "Main/Command.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE();

namespace Command
{
    void test(CompilerInstance& compiler)
    {
        sema(compiler);
        if (Stats::get().numErrors.load(std::memory_order_relaxed) != 0)
            return;

        const bool           runArtifact = compiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable;
        NativeBackendBuilder builder(compiler, runArtifact);
        builder.run();
    }
}

SWC_END_NAMESPACE();
