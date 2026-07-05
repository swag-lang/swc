#include "pch.h"
#include "Backend/Sanitizer/Checks/Check.UseAfterMove.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

void UseAfterMoveCheck::run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
{
    if (state.movedFrom.empty())
        return;

    // Plain loads only: address computations ('lea') are legitimate (re-initialization
    // through an out-parameter), and indexed forms cannot prove the accessed range.
    switch (inst.op)
    {
        case MicroInstrOpcode::LoadRegMem:
        case MicroInstrOpcode::LoadSignedExtRegMem:
        case MicroInstrOpcode::LoadZeroExtRegMem:
        case MicroInstrOpcode::LoadVecRegMem:
            break;
        default:
            return;
    }

    int64_t slot = 0;
    if (!sanitizer.resolveStackSlot(state, ops[def.memBaseOperandIndex].reg, ops[def.memOffsetOperandIndex].valueU64, slot))
        return;

    for (const auto& [rangeStart, rangeSize] : state.movedFrom)
    {
        if (slot >= rangeStart && slot < rangeStart + static_cast<int64_t>(rangeSize))
        {
            sanitizer.report(inst, DiagnosticId::safety_err_use_after_move);
            return;
        }
    }
}

SWC_END_NAMESPACE();
