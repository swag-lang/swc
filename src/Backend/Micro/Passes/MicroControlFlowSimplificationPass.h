#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroControlFlowSimplificationPass final : public MicroPass
{
public:
    // Simplify redundant labels/jumps and remove trivially unreachable code ranges.
    std::string_view name() const override { return "cfg-simplify"; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
