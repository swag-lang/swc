#pragma once
#include "Backend/Sanitizer/SanitizerCheck.h"

SWC_BEGIN_NAMESPACE();

// Reports a PROVEN use of a freed pointer. The engine marks the slot a pointer was
// loaded from when it is handed to a callee whose FREES summary covers that
// parameter ('SanitizerState::freedPtrSlots', must-join, revalidated by stores and
// cleared by calls). Dereferencing a value reloaded from such a slot is a
// use-after-free; handing it to a freeing callee again is a double free. Aliases
// give misses, never false positives.
class UseAfterFreeCheck final : public SanitizerCheck
{
public:
    Runtime::SafetyWhat safety() const override { return Runtime::SafetyWhat::Lifecycle; }
    void                run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) override;
};

SWC_END_NAMESPACE();
