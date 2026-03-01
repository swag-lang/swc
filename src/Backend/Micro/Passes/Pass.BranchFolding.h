#pragma once
#include "Backend/Micro/MicroPassManager.h"

SWC_BEGIN_NAMESPACE();

class MicroBranchFoldingPass final : public MicroPass
{
public:
    std::string_view name() const override { return "branch-fold"; }
    Result           run(MicroPassContext& context) override;

private:
    std::unordered_map<MicroReg, uint64_t> knownValues_;
    std::unordered_set<MicroLabelRef>      referencedLabels_;
    bool                                   compareValid_  = false;
    uint64_t                               compareLhs_    = 0;
    uint64_t                               compareRhs_    = 0;
    MicroOpBits                            compareOpBits_ = MicroOpBits::B64;
};

SWC_END_NAMESPACE();
