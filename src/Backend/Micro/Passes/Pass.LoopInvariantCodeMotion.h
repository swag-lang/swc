#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

// Pre-RA loop-invariant code motion on virtual registers.
//
// Hoists side-effect-free, loop-invariant value-producing instructions out of
// natural loops into the loop preheader (the fall-through region immediately
// before the loop header label). Targets the canonical wins: invariant address
// computations (`lea`), invariant memory loads (reducing per-iteration memory
// traffic), constant materialization, and register copies/extensions.
//
// Conservative by construction (see the .cpp for the full safety argument):
//   - only a fixed whitelist of opcodes that neither read/write CPU flags,
//     write memory, nor call is eligible;
//   - a hoisted instruction's destination must be a virtual register that is
//     defined exactly once in the whole function, so moving its single def can
//     never disturb a reused / loop-carried register (the class of bug that
//     sank earlier loop transforms in this backend);
//   - a memory load is hoisted only when the loop contains no store or call
//     (no aliasing writer) and the load dominates every back-edge tail, so it
//     already executed on every iteration and cannot be speculated into a fault.
class MicroLoopInvariantCodeMotionPass final : public MicroPass
{
public:
    std::string_view name() const override { return "licm"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
