#include "pch.h"
#include "Main/Command.h"
#include "Backend/Native/NativeBackend.h"
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

        const bool runArtifact = compiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable;
        (void) NativeBackend::run(compiler, runArtifact);
    }
}

SWC_END_NAMESPACE();
