#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

// Lays the local frame out again from the objects the optimized body still reaches.
//
// Lowering reserves a slot for every local of the function, including every local of
// every inlined callee, before the body is optimized. Promotion to registers, constant
// folding and dead-branch removal then leave most of those slots unreferenced, but the
// prologue keeps subtracting the whole layout: an allocation fast path inlined into a
// recursive function paid for the locals of the branches its constant arguments had
// folded away (compiler.optimization.129). The pass runs once on the converged pre-RA IR:
// it maps every surviving frame access to its object, drops the objects nothing reaches,
// packs the rest in their original order, and rewrites the displacements, the entry
// subtract and the releases. An access it cannot explain - a stack-pointer use at an
// unknown displacement, a frame address redefined by arithmetic, an access straddling two
// objects - keeps the frame as lowered. Debug builds keep it too, because the debug
// records locate every local by its lowering offset.
class MicroFrameCompactPass final : public MicroPass
{
public:
    std::string_view name() const override { return "frame-compact"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
