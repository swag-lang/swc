#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Hoists a loop-invariant spill reload out of its loop.
//
// The register allocator hands every value a whole-function register or none at
// all, ranked by how much it earns per unit of the register-time it occupies. A
// pointer a hot loop dereferences on every iteration earns enormously and lives
// for the whole function, so its density is microscopic and it loses to a
// short-lived value in some cold stretch. The allocator then reloads it from
// its stack home inside the loop, once per iteration, forever.
//
// This is that reload's live range split at the loop boundary. The load moves
// to the preheader and the register carries the value across the whole loop,
// which is sound exactly when nothing in the loop writes the slot or the
// register, and when the register holds nothing live at the preheader. Measured
// on bench/: the same loops compiled inside a small function already come out
// with no memory operations at all, so this closes a gap the code generator
// only has in large functions.
class MicroPostRaLoopHoistPass final : public MicroPass
{
public:
    std::string_view name() const override { return "post-ra-loop-hoist"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
