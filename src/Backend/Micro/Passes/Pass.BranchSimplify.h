#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Pre-RA branch simplification and control flow graph cleanup.
// Folds constant branches, removes unreachable blocks, and simplifies the CFG.
class MicroBranchSimplifyPass final : public MicroPass
{
public:
    std::string_view name() const override { return "branch-simplify"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
