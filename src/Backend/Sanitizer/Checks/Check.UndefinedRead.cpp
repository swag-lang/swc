#include "pch.h"
#include "Backend/Sanitizer/Checks/Check.UndefinedRead.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

void UndefinedReadCheck::run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
{
    if (state.undefinedInit.empty())
        return;

    // Plain loads only: address computations ('lea') are legitimate (initialization
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

    for (const auto& [rangeStart, rangeSize] : state.undefinedInit)
    {
        if (slot >= rangeStart && slot < rangeStart + static_cast<int64_t>(rangeSize))
        {
            sanitizer.report(inst, DiagnosticId::sanity_err_undefined_read);
            return;
        }
    }
}

SWC_END_NAMESPACE();
