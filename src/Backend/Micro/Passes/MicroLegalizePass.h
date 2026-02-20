#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroLegalizePass final : public MicroPass
{
public:
    // Enforces encoder constraints by rewriting unsupported operand forms.
    MicroPassKind kind() const override { return MicroPassKind::Legalize; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
