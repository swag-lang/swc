#include "pch.h"
#include "Backend/Sanitizer/Checks/NullDerefCheck.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

void NullDerefCheck::run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
{
    if (!def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
        return;

    // A `lea` only computes an address; it never faults. Real code legitimately forms
    // addresses from a null base (e.g. the data pointer of an empty, zero-length slice),
    // so only an actual load/store is a dereference.
    if (inst.op == MicroInstrOpcode::LoadAddrRegMem || inst.op == MicroInstrOpcode::LoadAddrAmcRegMem)
        return;

    if (sanitizer.getReg(state, ops[def.memBaseOperandIndex].reg).isZero())
        sanitizer.report(inst, DiagnosticId::safety_err_null_deref);
}

SWC_END_NAMESPACE();
