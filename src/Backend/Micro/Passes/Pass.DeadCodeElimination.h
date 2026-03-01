#pragma once
#include "Backend/Micro/MicroPassManager.h"

SWC_BEGIN_NAMESPACE();

class MicroDeadCodeEliminationPass final : public MicroPass
{
public:
    std::string_view name() const override { return "dce"; }
    Result           run(MicroPassContext& context) override;

private:
    std::unordered_map<MicroReg, MicroInstrRef> lastPureDefByReg_;
};

SWC_END_NAMESPACE();
