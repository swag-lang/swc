#pragma once
#include "Backend/Micro/MicroPassManager.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

// Pre-RA scheduling for register pressure: a pure, flag-free, single-use
// definition moves down to sit just before its one consumer in the same
// basic block.
//
// The front end emits a block in source order, so a run of declarations
// materializes every value before the first one is consumed - sixteen sample
// loads followed by the arithmetic that folds them keeps sixteen values live
// at once, and the allocator can only answer that with spills. Sinking each
// definition to its use makes a live range one instruction long, which is
// how the same block leaves clang's scheduler.
class MicroSinkToUsePass final : public MicroPass
{
public:
    std::string_view name() const override { return "sink-to-use"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
