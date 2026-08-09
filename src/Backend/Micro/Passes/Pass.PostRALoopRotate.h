#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

// Post-RA rotation of top-tested loops.
//
// A `while` lowers to a header that tests and a body that jumps back, so every
// iteration pays an unconditional jump on top of its test. clang-cl and MSVC
// both emit the rotated form, where the test itself is the back edge; csvagg's
// four byte scans are 6 instructions here against their 5, and that jump is the
// whole difference.
//
// This runs after register allocation on purpose. The same rewrite pre-RA also
// removes the jump, but it moves where the loop header sits, and the allocator
// reads loop structure: csvagg's digit loops lost their accumulator's register
// and went from 2 memory operations per iteration to 4 while its scans
// improved. After allocation there are no registers left to lose, so the
// transformation is purely the jump it removes.
class MicroPostRaLoopRotatePass final : public MicroPass
{
public:
    std::string_view name() const override { return "post-ra-loop-rotate"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
