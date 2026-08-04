#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

// Pre-RA full unrolling of small counted loops.
// A bottom-tested loop whose counter starts at a constant, steps by a
// constant, and exits on a compare against a constant runs a knowable number
// of times; when that number and the body are both small, the copies replace
// the loop and the counter becomes a per-copy constant. The pre-RA
// optimization loop then folds the constant through address modes and
// extensions, which is where the real win lives: a four-element intersection
// kernel turns into straight-line code with direct displacements.
class MicroLoopUnrollPass final : public MicroPass
{
public:
    std::string_view name() const override { return "loop-unroll"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
