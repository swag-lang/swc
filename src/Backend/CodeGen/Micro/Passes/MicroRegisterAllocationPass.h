#pragma once
#include "Backend/CodeGen/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroRegisterAllocationPass final : public MicroPass
{
public:
    MicroPassKind kind() const override { return MicroPassKind::RegisterAllocation; }
    void          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
