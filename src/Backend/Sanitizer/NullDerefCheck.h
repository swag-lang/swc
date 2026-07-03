#pragma once
#include "Backend/Sanitizer/SanitizerCheck.h"

SWC_BEGIN_NAMESPACE();

// Reports a dereference (an actual load/store, not an address computation) through a
// pointer the sanitizer proved is null on every path.
class NullDerefCheck final : public SanitizerCheck
{
public:
    Runtime::SafetyWhat safety() const override { return Runtime::SafetyWhat::Null; }
    void                run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) override;
};

SWC_END_NAMESPACE();
