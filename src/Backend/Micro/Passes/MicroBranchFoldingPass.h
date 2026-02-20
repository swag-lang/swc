#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroBranchFoldingPass final : public MicroPass
{
public:
    // Fold conditional branches when compare inputs are known at compile time.
    MicroPassKind kind() const override { return MicroPassKind::BranchFolding; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
