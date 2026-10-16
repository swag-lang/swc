#include "pch.h"
#include "Backend/Sanitizer/Checks/Check.UseAfterMove.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

void UseAfterMoveCheck::run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
{
    const DiagnosticId id = def.flags.has(MicroInstrFlagsE::WritesMemory) ? DiagnosticId::sanity_err_write_after_move : DiagnosticId::sanity_err_use_after_move;
    sanitizer.reportAccessToMovedRange(inst, def, ops, state, id);
}

SWC_END_NAMESPACE();
