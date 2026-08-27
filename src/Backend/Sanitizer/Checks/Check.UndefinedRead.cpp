#include "pch.h"
#include "Backend/Sanitizer/Checks/Check.UndefinedRead.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

void UndefinedReadCheck::run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
{
    sanitizer.reportLoadFromUndefinedRange(inst, def, ops, state, DiagnosticId::sanity_err_undefined_read);
}

SWC_END_NAMESPACE();
