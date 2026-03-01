#pragma once
#include "Backend/Micro/MicroPassManager.h"

SWC_BEGIN_NAMESPACE();

class MicroStrengthReductionPass final : public MicroPass
{
public:
    std::string_view name() const override { return "strength-reduction"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
