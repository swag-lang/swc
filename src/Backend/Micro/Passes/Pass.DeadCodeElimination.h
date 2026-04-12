#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Pre-RA dead code elimination on virtual registers.
// Removes side-effect-free instructions whose results are never used.
// Uses backward liveness analysis over the CFG on virtual registers.
class MicroDeadCodeEliminationPass final : public MicroPass
{
public:
    std::string_view name() const override { return "dce"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
