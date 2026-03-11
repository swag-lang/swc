#pragma once

#include "Backend/Debug/DebugInfo.h"

SWC_BEGIN_NAMESPACE();

class DebugInfoCodeView final : public DebugInfo
{
public:
    Result buildObject(DebugInfoObjectResult& outResult, const DebugInfoObjectRequest& request) override;
    bool   emitJitArtifact(JitDebugArtifact& outArtifact, const JitDebugRequest& request) override;
};

SWC_END_NAMESPACE();
