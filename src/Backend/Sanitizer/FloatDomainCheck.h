#pragma once
#include "Backend/Sanitizer/SanitizerCheck.h"

SWC_BEGIN_NAMESPACE();

// Reports a float math operation whose operand the sanitizer proved is a constant
// outside the operation's domain, mirroring the runtime `Math` safety checks:
// - `sqrt(x)` with `x < 0` (lowers to an inline `FloatSqrt` micro-op);
// - `log/log2/log10(x)` with `x < 0` and `asin/acos(x)` with `x` outside [-1, 1]
//   (lower to calls to the `@log`/`@asin`/... runtime functions, whose first float
//   argument register is inspected at the call site).
class FloatDomainCheck final : public SanitizerCheck
{
public:
    Runtime::SafetyWhat safety() const override { return Runtime::SafetyWhat::Math; }
    void                run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) override;
};

SWC_END_NAMESPACE();
