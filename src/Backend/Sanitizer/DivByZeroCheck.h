#pragma once
#include "Backend/Sanitizer/SanitizerCheck.h"

SWC_BEGIN_NAMESPACE();

// Reports an integer division or modulo whose divisor the sanitizer proved is zero on
// every path. Float division is not checked (division by zero yields infinity, not a
// fault).
class DivByZeroCheck final : public SanitizerCheck
{
public:
    Runtime::SafetyWhat safety() const override { return Runtime::SafetyWhat::Math; }
    void                run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) override;
};

SWC_END_NAMESPACE();
