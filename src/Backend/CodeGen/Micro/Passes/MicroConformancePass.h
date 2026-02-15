#pragma once
#include "Backend/CodeGen/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroConformancePass final : public MicroPass
{
public:
    MicroPassKind kind() const override { return MicroPassKind::Conformance; }
    void          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
