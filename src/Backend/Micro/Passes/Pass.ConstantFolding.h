#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Pre-RA constant folding on virtual registers.
// Propagates known constants through register operations and folds computable expressions.
// Runs before register allocation so it sees the full virtual register space.
class MicroConstantFoldingPass final : public MicroPass
{
public:
    std::string_view name() const override { return "const-fold"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
