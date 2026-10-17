#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Splits a 16-byte load that narrower stores of the same loop write into two
// 8-byte loads.
//
// A load that reads the bytes of a recent store takes them from the store buffer
// only when that one store covers the whole load. Two 8-byte stores followed by a
// 16-byte load of both cannot forward: the load waits until the stores reach the
// cache, a dozen cycles or more, and when the stores and the load sit on a
// loop-carried chain that wait repeats on every trip. The vectorizers produce
// exactly that shape when scalar code writes two adjacent fields and a packed
// update reads them back - n-body stores each velocity component on its own and
// then advances the positions two components at a time.
//
// Each half of the split load is covered by one of the stores, so both forward.
// The pass splits only when it can prove the overlap: the load and the store
// address the same object, a base value plus a constant offset that may step by
// a constant on each trip of a loop, and their bytes meet for some trip. Both must
// sit in one loop, or the store must precede a load that is in none: a store
// before a loop delays only the first trip. A store narrower than a half, or one
// straddling the two halves, would still block a half, and leaves the load whole.
class MicroStoreForwardSplitPass final : public MicroPass
{
public:
    std::string_view name() const override { return "store-forward-split"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
