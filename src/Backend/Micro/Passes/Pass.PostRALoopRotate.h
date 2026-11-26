#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

// Post-RA layout of loop tests and short step blocks.
//
// A `while` lowers to a header that tests and a body that jumps back, so every
// iteration pays an unconditional jump on top of its test. clang-cl and MSVC
// both emit the rotated form, where the test itself is the back edge.
//
// The allocator uses loop boundaries when ranking spill candidates. Rotating
// the test after allocation preserves its register assignments and also sees
// the allocator's insertions around the header test.
class MicroPostRaLoopRotatePass final : public MicroPass
{
public:
    std::string_view name() const override { return "post-ra-loop-rotate"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
