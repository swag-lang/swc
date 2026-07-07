#include "pch.h"
#include "Backend/Sanitizer/Checks/Check.BoundCheck.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

void BoundCheckCheck::run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
{
    // A mutated stack base shifts every computed frame offset: the extents cannot be
    // trusted, only slot-relative facts survive.
    if (!sanitizer.stackBaseStable())
        return;

    if (!def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
        return;

    // A 'lea' only computes an address; one-past-the-end is legal to form.
    if (inst.op == MicroInstrOpcode::LoadAddrRegMem || inst.op == MicroInstrOpcode::LoadAddrAmcRegMem)
        return;

    const SanitizerValue base = sanitizer.getReg(state, ops[def.memBaseOperandIndex].reg);
    if (!base.hasStackOrigin())
        return;

    int64_t  slotStart = 0;
    uint64_t slotSize  = 0;
    if (!sanitizer.findLocalSlotExtents(base.stackOrigin, slotStart, slotSize))
        return;

    // Conservative single-byte access test: flagging only the first accessed byte is
    // enough for a provably out-of-range start and can never over-report.
    const int64_t accessStart = base.stackOffset + static_cast<int64_t>(ops[def.memOffsetOperandIndex].valueU64);
    if (accessStart < slotStart || accessStart >= slotStart + static_cast<int64_t>(slotSize))
        sanitizer.report(inst, DiagnosticId::sanity_err_out_of_bounds);
}

SWC_END_NAMESPACE();
