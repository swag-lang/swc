#include "pch.h"
#include "Backend/Sanitizer/Checks/Check.UndefinedRead.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

void UndefinedReadCheck::run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
{
    sanitizer.reportLoadFromPoisonedRange(inst, def, ops, state, state.undefinedInit, DiagnosticId::sanity_err_undefined_read);
}

SWC_END_NAMESPACE();
