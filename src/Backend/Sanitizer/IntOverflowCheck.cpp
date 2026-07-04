#include "pch.h"
#include "Backend/Sanitizer/IntOverflowCheck.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isSignedDivOrModulo(MicroOp op)
    {
        return op == MicroOp::DivideSigned || op == MicroOp::ModuloSigned;
    }

    bool isMinDividedByMinusOne(uint64_t dividend, uint64_t divisor, MicroOpBits opBits)
    {
        const uint32_t bits = static_cast<uint32_t>(opBits);
        if (bits < 8 || bits > 64)
            return false;
        const uint64_t mask      = bits == 64 ? ~0ull : (1ull << bits) - 1;
        const uint64_t signedMin = 1ull << (bits - 1);
        return (divisor & mask) == mask && (dividend & mask) == signedMin;
    }
}

void IntOverflowCheck::run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef&, const MicroInstrOperand* ops)
{
    if (!ops)
        return;

    // `dst = dst <op> divisor`, with dst read as the dividend.
    if (inst.op == MicroInstrOpcode::OpBinaryRegReg && isSignedDivOrModulo(ops[3].microOp))
    {
        const SanitizerValue dividend = sanitizer.getReg(state, ops[0].reg);
        const SanitizerValue divisor  = sanitizer.getReg(state, ops[1].reg);
        if (dividend.isConstant() && divisor.isConstant() &&
            isMinDividedByMinusOne(dividend.constant, divisor.constant, ops[2].opBits))
            sanitizer.report(inst, DiagnosticId::safety_err_integer_overflow);
        return;
    }

    if (inst.op == MicroInstrOpcode::OpBinaryRegImm && isSignedDivOrModulo(ops[2].microOp))
    {
        const SanitizerValue dividend = sanitizer.getReg(state, ops[0].reg);
        if (dividend.isConstant() &&
            isMinDividedByMinusOne(dividend.constant, ops[3].valueU64, ops[1].opBits))
            sanitizer.report(inst, DiagnosticId::safety_err_integer_overflow);
    }
}

SWC_END_NAMESPACE();
