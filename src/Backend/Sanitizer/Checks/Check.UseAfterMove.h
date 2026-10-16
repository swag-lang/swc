#pragma once
#include "Backend/Sanitizer/SanitizerCheck.h"

SWC_BEGIN_NAMESPACE();

// Reports a read or a pre-existing pointer's write into storage abandoned by a '#move'/'#relocate'
// (moved-from and not reset) before any re-initialization. CodeGen plants a
// 'SanityInvalidate' marker at the abandonment point; the engine tracks the marked
// frame ranges ('SanitizerState::movedFrom', must-be-moved on every path, stores
// revalidate, calls clear). Fresh addresses and direct stores can reinitialize storage.
class UseAfterMoveCheck final : public SanitizerCheck
{
public:
    Runtime::SafetyWhat safety() const override { return Runtime::SafetyWhat::Lifecycle; }
    uint8_t             interests() const override { return static_cast<uint8_t>(SanitizerCheckInterest::MovedStorage); }
    void                run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) override;
};

SWC_END_NAMESPACE();
