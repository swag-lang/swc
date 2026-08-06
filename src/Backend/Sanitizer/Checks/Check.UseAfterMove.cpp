#include "pch.h"
#include "Backend/Sanitizer/Checks/Check.UseAfterMove.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

void UseAfterMoveCheck::run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
{
    sanitizer.reportLoadFromPoisonedRange(inst, def, ops, state, state.movedFrom, DiagnosticId::sanity_err_use_after_move);
}

SWC_END_NAMESPACE();
