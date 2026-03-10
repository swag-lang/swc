#include "pch.h"
#include "Backend/Debug/DebugInfo.h"

SWC_BEGIN_NAMESPACE();

namespace DebugInfoPrivate
{
    Result buildWindowsObject(const DebugInfoObjectRequest& request, DebugInfoObjectResult& outResult);
    bool   emitWindowsJitArtifact(const JitDebugRequest& request, JitDebugArtifact& outArtifact);
}

Result DebugInfo::buildObject(const DebugInfoObjectRequest& request, DebugInfoObjectResult& outResult)
{
    switch (request.targetOs)
    {
        case Runtime::TargetOs::Windows:
            return DebugInfoPrivate::buildWindowsObject(request, outResult);
    }

    SWC_UNREACHABLE();
}

bool DebugInfo::emitJitArtifact(const JitDebugRequest& request, JitDebugArtifact& outArtifact)
{
    switch (request.targetOs)
    {
        case Runtime::TargetOs::Windows:
            return DebugInfoPrivate::emitWindowsJitArtifact(request, outArtifact);
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
