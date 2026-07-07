#pragma once
#include "Backend/Sanitizer/SanitizerCheck.h"

SWC_BEGIN_NAMESPACE();

// Reports a load/store through an address PROVABLY outside the storage of the
// variable it was derived from: an indexed access whose base and constant index the
// engine tracked exactly ('var i = 5; a[i]' on a 4-element array). The address keeps
// the frame offset it was FORMED from ('SanitizerValue::stackOrigin'); the access is
// compared against the extents of the declared variable containing that origin, so a
// pointer legitimately targeting another variable never matches. Address computations
// ('lea') are not flagged: forming a one-past-the-end address is legal, dereferencing
// it is not.
class BoundCheckCheck final : public SanitizerCheck
{
public:
    Runtime::SafetyWhat safety() const override { return Runtime::SafetyWhat::BoundCheck; }
    void                run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) override;
};

SWC_END_NAMESPACE();
