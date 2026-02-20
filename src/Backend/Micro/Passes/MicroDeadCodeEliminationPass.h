#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroDeadCodeEliminationPass final : public MicroPass
{
public:
    // Remove dead side-effect-free instructions using backward register liveness.
    MicroPassKind kind() const override { return MicroPassKind::DeadCodeElimination; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
