#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Loop-carried load forwarding, after LLVM's LoopLoadElimination.
//
// In a loop that walks an array with an index stepped by a constant, a load
// often reads the element the previous trip stored: a dynamic-programming row
// reads `row[i]` right after the previous trip stored `row[i + 1]`. Through
// memory, that dependence costs a store-forwarding round trip on every trip
// of the recurrence. The stored value is carried in a register instead: the
// store also copies it to the register, the load becomes a copy from the
// register, and the loop's preheader loads the first trip's value.
//
// A later load can supply the next trip too, provided every store misses the
// carried element. Run once after vectorization, on converged loop shapes.
// All eligible loops are planned before any instruction storage is changed.
//
// Only a rotated single-block loop qualifies: its body is entered by falling
// through from the preheader and leaves only through its latch, so the first
// trip always executes the replaced load and the preheader load reads the
// same address it would. The producer must run after the load in the body and
// access exactly the element the next trip loads (same base, index, scale and
// width; displacement one stride ahead). Every other store of the body must be
// provably disjoint from that element at both index values it may run with:
// same root, same index and scale, and non-overlapping constant offsets.
// Calls and stores the pass cannot place keep the loads.
class MicroLoopLoadForwardPass final : public MicroPass
{
public:
    std::string_view name() const override { return "loop-load-forward"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
