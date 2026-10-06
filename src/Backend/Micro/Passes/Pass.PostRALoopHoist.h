#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Removes frame traffic left after interval allocation. Invariant reloads and
// persistent argument copies move to a loop preheader; simple accumulators keep
// their assigned register across iterations. More complex private integer spills
// can use a caller-saved SIMD register that is free throughout the loop, with one
// seed before entry and a coherent write-back at each exclusive exit. Calls,
// aliases, register liveness and unsupported stack accesses bound these rewrites.
class MicroPostRaLoopHoistPass final : public MicroPass
{
public:
    std::string_view name() const override { return "post-ra-loop-hoist"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
