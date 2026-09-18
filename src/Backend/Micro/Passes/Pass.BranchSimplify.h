#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

// Pre-RA branch simplification and control flow graph cleanup.
// Folds constant branches, removes unreachable blocks, and simplifies the CFG.
class MicroBranchSimplifyPass final : public MicroPass
{
public:
    MicroBranchSimplifyPass() = default;
    // The late instance runs once on the converged pre-RA IR and only gives
    // short-circuit exits the constant their branch pins: earlier, it would
    // take chains the range and branchless folds of later sweeps still want.
    explicit MicroBranchSimplifyPass(bool late) :
        late_(late)
    {
    }

    std::string_view name() const override { return late_ ? "branch-simplify-late" : "branch-simplify"; }
    Result           run(MicroPassContext& context) override;

private:
    bool late_ = false;
};

SWC_END_NAMESPACE();
