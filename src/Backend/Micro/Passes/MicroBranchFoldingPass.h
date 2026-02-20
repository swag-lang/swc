#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroBranchFoldingPass final : public MicroPass
{
public:
    // Fold conditional branches when compare inputs are known at compile time.
    std::string_view name() const override { return "branch-fold"; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
