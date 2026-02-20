#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroControlFlowSimplificationPass final : public MicroPass
{
public:
    // Simplify redundant labels/jumps and remove trivially unreachable code ranges.
    MicroPassKind kind() const override { return MicroPassKind::ControlFlowSimplification; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
