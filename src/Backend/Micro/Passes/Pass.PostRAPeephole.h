#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Post-RA peephole optimization on physical registers.
// Lightweight cleanup after register allocation: remove redundant no-op
// instructions, erase dead compares, and leave room for more target-specific
// post-RA cleanups without growing one monolithic pass.
class MicroPostRAPeepholePass final : public MicroPass
{
public:
    std::string_view name() const override { return "post-ra-peephole"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
