#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Removes frame traffic left after interval allocation. Invariant reloads and
// persistent argument copies move to a loop preheader; simple accumulators keep
// their assigned register across iterations. More complex private integer spills
// can use a caller-saved SIMD register that is free throughout the loop, with one
// seed on each entry and a coherent write-back at each exclusive exit. Private
// homes can cross conditional calls by restoring clobbered caches after them;
// written homes retain their stores to keep memory coherent on all exits.
// Aliases, liveness and stack changes bound these rewrites.
class MicroPostRaLoopHoistPass final : public MicroPass
{
public:
    std::string_view name() const override { return "post-ra-loop-hoist"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
