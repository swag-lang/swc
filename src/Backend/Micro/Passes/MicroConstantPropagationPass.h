#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroConstantPropagationPass final : public MicroPass
{
public:
    // Propagate integer constants through register-only computations.
    MicroPassKind kind() const override { return MicroPassKind::ConstantPropagation; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
