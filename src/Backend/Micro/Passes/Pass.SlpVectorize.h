#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Superword-level auto-vectorization on the pre-RA virtual-register IR.
//
// Runs once after the pre-RA optimization loop has converged, so it sees the
// canonical scalar shape: hoisted address computations, folded copies, and the
// loop bodies as straight-line blocks. It rebuilds each block's dataflow as a
// 32-bit-lane value graph with in-block store-to-load forwarding, seeds on
// groups of four adjacent 32-bit stores, grows isomorphic trees down to
// adjacent-load leaves, and replaces the matched stores with 128-bit packed
// code. The scalar computation is left in place and dies in the cleanup sweep
// that follows.
//
// Gated by the build configuration: it only fires when backend optimization and
// vectorization are both on, which is the 'release' preset. The 128-bit packed
// forms it emits are part of the x86-64-v3 baseline every target provides, so
// there is no instruction-set gate on top of that policy.
class MicroSlpVectorizePass final : public MicroPass
{
public:
    std::string_view name() const override { return "slp-vectorize"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
