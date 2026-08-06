#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Promotes a loop's 128-bit stack chunks from memory residence to a
// loop-carried vector register.
//
// The SLP vectorizer works block by block, so a vectorized loop body reloads
// its packed state from the frame at the top of every iteration and stores it
// back at the bottom: the loop-carried value round-trips through memory on the
// store-to-load forwarding latency chain, ten times per ChaCha20 block, where
// hand-written SIMD keeps the row vectors in registers for the whole loop.
// This pass claims the loop region the SLP pass cannot see: the packed load of
// a frame chunk moves to the preheader, the packed store moves to the loop
// exit, and inside the body both become plain 128-bit register copies of one
// fresh virtual register, which the register allocator then keeps resident
// across the back-edge (or, failing that, gives one stable spill home - never
// worse than the memory residence it replaces).
//
// Soundness rests on the frame being private to the loop: a chunk is promoted
// only when it lives on the stack, every access of the loop body resolves to a
// provably disjoint location (the frame chunk itself, another frame offset, or
// one incoming parameter, which existed before this frame and cannot alias
// it), the body contains no call, and the loop has a unique fall-through exit
// on which the store can be sunk. One loop is transformed per run - innermost
// first - and the enclosing optimization loop re-runs the pass, so a chunk
// climbs one loop level per sweep until it reaches the outermost loop whose
// every access is the packed pair.
class MicroVecLoopPromotePass final : public MicroPass
{
public:
    std::string_view name() const override { return "vec-loop-promote"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
