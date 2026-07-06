#include "pch.h"
#include "Backend/Sanitizer/Checks/Check.DivByZero.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isIntegerDivOrModulo(MicroOp op)
    {
        return op == MicroOp::DivideSigned || op == MicroOp::DivideUnsigned ||
               op == MicroOp::ModuloSigned || op == MicroOp::ModuloUnsigned;
    }
}

void DivByZeroCheck::run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef&, const MicroInstrOperand* ops)
{
    if (!ops)
        return;

    // `dst = dst <op> divisor`.
    switch (inst.op)
    {
        case MicroInstrOpcode::OpBinaryRegImm:
            // ops: [dst, opBits, microOp, imm-divisor]
            if (isIntegerDivOrModulo(ops[2].microOp) && ops[3].valueU64 == 0)
                sanitizer.report(inst, DiagnosticId::sanity_err_division_zero);
            return;

        case MicroInstrOpcode::OpBinaryRegReg:
            // ops: [dst, src-divisor, opBits, microOp]
            if (isIntegerDivOrModulo(ops[3].microOp) && sanitizer.getReg(state, ops[1].reg).isZero())
                sanitizer.report(inst, DiagnosticId::sanity_err_division_zero);
            return;

        default:
            return;
    }
}

SWC_END_NAMESPACE();
