#pragma once
#include "Backend/Sanitizer/SanitizerCheck.h"

SWC_BEGIN_NAMESPACE();

// Reports a function returning the address of one of its own locals: the frame dies
// with the return, so the returned pointer/reference is always dangling. The engine
// already proves this — a value derived from the local stack base is tracked as
// `StackAddr` — so the check fires when such a value sits in the return register at a
// `Ret` and the function's return type is a pointer or reference.
class StackEscapeCheck final : public SanitizerCheck
{
public:
    Runtime::SafetyWhat safety() const override { return Runtime::SafetyWhat::Memory; }
    void                run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) override;
};

SWC_END_NAMESPACE();
