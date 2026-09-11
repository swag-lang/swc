#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

// Pre-RA strength reduction of the products of a loop counter.
//
// A counted loop that addresses its rows as `base + row * stride` multiplies on
// every trip: the lowering is a copy of the counter followed by the multiply.
// The product is an affine function of the counter, so it is carried instead
// of recomputed: an accumulator starts in the preheader at the product's
// value on entry and advances by `stride * step` wherever the counter
// advances, and the multiply becomes a copy of the accumulator. This is the
// operator strength reduction of Cocke and Kennedy, the part of LLVM's loop
// strength reduction that pays on x86, where a multiply is three cycles on the
// address path and an add is one.
//
// A counter is a virtual register with exactly one definition inside the loop,
// an addition or subtraction of an immediate. A stride is a register no
// instruction of the loop defines, or an immediate. Everything else keeps its
// multiply.
class MicroInductionVariablePass final : public MicroPass
{
public:
    std::string_view name() const override { return "iv-reduce"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
