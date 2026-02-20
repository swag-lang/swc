#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroStrengthReductionPass final : public MicroPass
{
public:
    // Replace expensive integer arithmetic forms by cheaper equivalent instructions.
    MicroPassKind kind() const override { return MicroPassKind::StrengthReduction; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
