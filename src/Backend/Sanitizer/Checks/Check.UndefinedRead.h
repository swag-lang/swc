#pragma once
#include "Backend/Sanitizer/SanitizerCheck.h"

SWC_BEGIN_NAMESPACE();

// Reports a read from a local declared with an explicit '= undefined' initializer
// before any store reaches it. CodeGen plants a 'SanityUndefined' marker at the
// declaration; the engine tracks the marked frame ranges
// ('SanitizerState::undefinedInit', must-be-undefined on every path, stores
// initialize, calls clear), so the check only has to test loads against the ranges.
class UndefinedReadCheck final : public SanitizerCheck
{
public:
    Runtime::SafetyWhat safety() const override { return Runtime::SafetyWhat::Lifecycle; }
    void                run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) override;
};

SWC_END_NAMESPACE();
