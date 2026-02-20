#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroDeadCodeEliminationPass final : public MicroPass
{
public:
    // Remove dead side-effect-free instructions using backward register liveness.
    std::string_view name() const override { return "dce"; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
