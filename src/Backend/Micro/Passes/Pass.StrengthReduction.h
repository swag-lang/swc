#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Pre-RA strength reduction on virtual registers.
// Replaces expensive arithmetic with cheaper equivalent forms.
class MicroStrengthReductionPass final : public MicroPass
{
public:
    std::string_view name() const override { return "strength-reduce"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
