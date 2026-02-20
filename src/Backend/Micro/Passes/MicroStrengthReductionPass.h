#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroStrengthReductionPass final : public MicroPass
{
public:
    // Replace expensive integer arithmetic forms by cheaper equivalent instructions.
    std::string_view name() const override { return "strength-reduction"; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
