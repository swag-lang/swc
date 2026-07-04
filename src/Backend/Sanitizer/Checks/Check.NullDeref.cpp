#include "pch.h"
#include "Backend/Sanitizer/Checks/Check.NullDeref.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

void NullDerefCheck::run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
{
    // Calling through a null function pointer (a never-assigned lambda/closure) faults
    // just like a data dereference.
    if (inst.op == MicroInstrOpcode::CallIndirect)
    {
        if (ops && sanitizer.getReg(state, ops[0].reg).isZero())
            sanitizer.report(inst, DiagnosticId::safety_err_null_call);
        return;
    }

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
