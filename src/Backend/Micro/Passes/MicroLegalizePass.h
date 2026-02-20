#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroLegalizePass final : public MicroPass
{
public:
    // Enforces encoder constraints by rewriting unsupported operand forms.
    std::string_view name() const override { return "legalize"; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
