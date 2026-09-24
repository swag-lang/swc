#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"
#include <vector>

SWC_BEGIN_NAMESPACE();

// Pre-RA dead code elimination on virtual registers.
// Removes side-effect-free instructions whose results are never used.
// Uses backward liveness analysis over the CFG on virtual registers.
class MicroDeadCodeEliminationPass final : public MicroPass
{
public:
    std::string_view name() const override { return "dce"; }
    Result           run(MicroPassContext& context) override;

private:
    // The pass lives on a compiler worker across functions. Both buffers are
    // overwritten by collectUsedValues before each use.
    std::vector<uint8_t>  usedValues_;
    std::vector<uint32_t> worklist_;
};

SWC_END_NAMESPACE();
