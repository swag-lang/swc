#include "pch.h"
#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

namespace NativeBackend
{
    Result run(CompilerInstance& compiler, const bool runArtifact)
    {
        NativeBackendBuilder builder(compiler, runArtifact);
        return builder.run();
    }
}

SWC_END_NAMESPACE();
