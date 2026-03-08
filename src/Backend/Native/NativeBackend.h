#pragma once

SWC_BEGIN_NAMESPACE();

class CompilerInstance;

namespace NativeBackend
{
    Result run(CompilerInstance& compiler, bool runArtifact);
}

SWC_END_NAMESPACE();
