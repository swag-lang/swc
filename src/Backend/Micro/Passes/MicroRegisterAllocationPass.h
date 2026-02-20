#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroRegisterAllocationPass final : public MicroPass
{
public:
    // Lowers virtual registers to physical registers and inserts spill/reload operations.
    MicroPassKind kind() const override { return MicroPassKind::RegisterAllocation; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
