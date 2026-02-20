#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroConstantPropagationPass final : public MicroPass
{
public:
    // Propagate integer constants through register-only computations.
    std::string_view name() const override { return "const-prop"; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
