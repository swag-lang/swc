#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

// Pre-RA strength reduction on virtual registers.
// Replaces expensive arithmetic with cheaper equivalent forms.
class MicroStrengthReductionPass final : public MicroPass
{
public:
    MicroStrengthReductionPass() = default;

    // The instance inside the pre-RA loop leaves a signed division by a
    // constant alone. Its dividend is often proved non-negative only once
    // the loop has put the value and the test that bounds it in registers,
    // and an expansion made before that can no longer become the unsigned
    // form. The late instance runs once on the converged IR and expands
    // what is still signed.
    explicit MicroStrengthReductionPass(bool deferSignedDivision) :
        deferSignedDivision_(deferSignedDivision)
    {
    }

    std::string_view name() const override { return deferSignedDivision_ ? "strength-reduce" : "strength-reduce-late"; }
    Result           run(MicroPassContext& context) override;

private:
    bool deferSignedDivision_ = false;
};

SWC_END_NAMESPACE();
