#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Post-RA peephole optimization on physical registers.
// Lightweight cleanup after register allocation: addressing mode folding,
// nop removal, adjacent store merging, dead compare elimination.
// This is intentionally small — the heavy lifting is done pre-RA.
class MicroPostRAPeepholePass final : public MicroPass
{
public:
    std::string_view name() const override { return "post-ra-peephole"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
