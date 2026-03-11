#include "pch.h"
#include "Backend/Debug/DebugInfo.h"
#include "Backend/Debug/DebugInfoCodeView.h"

SWC_BEGIN_NAMESPACE();

std::unique_ptr<DebugInfo> DebugInfo::create(const Runtime::TargetOs targetOs)
{
    switch (targetOs)
    {
        case Runtime::TargetOs::Windows:
            return std::make_unique<DebugInfoCodeView>();
    }

    SWC_UNREACHABLE();
}

Result DebugInfo::buildObject(const DebugInfoObjectRequest& request, DebugInfoObjectResult& outResult)
{
    const auto debugInfo = create(request.targetOs);
    return debugInfo->buildObject(outResult, request);
}

bool DebugInfo::emitJitArtifact(const JitDebugRequest& request, JitDebugArtifact& outArtifact)
{
    const auto debugInfo = create(request.targetOs);
    return debugInfo->emitJitArtifact(outArtifact, request);
}

SWC_END_NAMESPACE();
