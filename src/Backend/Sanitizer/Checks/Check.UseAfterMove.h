#pragma once
#include "Backend/Sanitizer/SanitizerCheck.h"

SWC_BEGIN_NAMESPACE();

// Reports a read from a local whose storage was abandoned by a '#move'/'#relocate'
// (moved-from and not reset) before any re-initialization. CodeGen plants a
// 'SanityInvalidate' marker at the abandonment point; the engine tracks the marked
// frame ranges ('SanitizerState::movedFrom', must-be-moved on every path, stores
// revalidate, calls clear), so the check only has to test loads against the ranges.
class UseAfterMoveCheck final : public SanitizerCheck
{
public:
    Runtime::SafetyWhat safety() const override { return Runtime::SafetyWhat::Lifecycle; }
    void                run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) override;
};

SWC_END_NAMESPACE();
