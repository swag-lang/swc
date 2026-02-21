#include "pch.h"
#include "Backend/Micro/MicroOptimization.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isIdentityBinaryImm(MicroOp op, uint64_t value, MicroOpBits opBits)
    {
        switch (op)
        {
            case MicroOp::Add:
            case MicroOp::Subtract:
            case MicroOp::Or:
            case MicroOp::Xor:
            case MicroOp::ShiftLeft:
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticRight:
                return value == 0;
            case MicroOp::And:
            {
                const uint64_t mask = getOpBitsMask(opBits);
                return mask != 0 && value == mask;
            }
            default:
                return false;
        }
    }

    bool isNoOpLoadRegReg(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        return inst.numOperands >= 2 && ops[0].reg == ops[1].reg;
    }

    bool isNoOpLoadAddrRegMem(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        SWC_UNUSED(inst);
        if (ops[1].reg.isInstructionPointer())
            return false;
        return ops[3].valueU64 == 0 && ops[0].reg == ops[1].reg;
    }

    bool isNoOpLoadCondRegReg(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        return inst.numOperands >= 4 && ops[3].opBits == MicroOpBits::B64 && ops[0].reg == ops[1].reg;
    }

    bool isNoOpOpBinaryRegReg(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        SWC_UNUSED(inst);
        return ops[3].microOp == MicroOp::Exchange && ops[0].reg == ops[1].reg;
    }

    bool isNoOpOpBinaryRegImm(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        SWC_UNUSED(inst);
        return isIdentityBinaryImm(ops[2].microOp, ops[3].valueU64, ops[1].opBits);
    }
}

bool MicroOptimization::isNoOpEncoderInstruction(const MicroInstr& inst, const MicroInstrOperand* ops)
{
    if (!ops && inst.numOperands != 0)
        return false;

    switch (inst.op)
    {
        case MicroInstrOpcode::End:
        case MicroInstrOpcode::Label:
        case MicroInstrOpcode::Debug:
        case MicroInstrOpcode::Push:
        case MicroInstrOpcode::Pop:
        case MicroInstrOpcode::Ret:
        case MicroInstrOpcode::CallIndirect:
        case MicroInstrOpcode::JumpTable:
        case MicroInstrOpcode::JumpCond:
        case MicroInstrOpcode::JumpReg:
        case MicroInstrOpcode::JumpCondImm:
        case MicroInstrOpcode::LoadRegImm:
        case MicroInstrOpcode::LoadRegPtrImm:
        case MicroInstrOpcode::LoadRegMem:
        case MicroInstrOpcode::LoadMemReg:
        case MicroInstrOpcode::LoadMemImm:
        case MicroInstrOpcode::LoadSignedExtRegMem:
        case MicroInstrOpcode::LoadZeroExtRegMem:
        case MicroInstrOpcode::LoadSignedExtRegReg:
        case MicroInstrOpcode::LoadZeroExtRegReg:
        case MicroInstrOpcode::LoadAmcRegMem:
        case MicroInstrOpcode::LoadAmcMemReg:
        case MicroInstrOpcode::LoadAmcMemImm:
        case MicroInstrOpcode::LoadAddrAmcRegMem:
        case MicroInstrOpcode::CmpRegReg:
        case MicroInstrOpcode::CmpRegZero:
        case MicroInstrOpcode::CmpRegImm:
        case MicroInstrOpcode::CmpMemReg:
        case MicroInstrOpcode::CmpMemImm:
        case MicroInstrOpcode::SetCondReg:
        case MicroInstrOpcode::ClearReg:
        case MicroInstrOpcode::OpUnaryMem:
        case MicroInstrOpcode::OpUnaryReg:
        case MicroInstrOpcode::OpBinaryRegMem:
        case MicroInstrOpcode::OpBinaryMemReg:
        case MicroInstrOpcode::OpBinaryMemImm:
        case MicroInstrOpcode::OpTernaryRegRegReg:
            return false;
        case MicroInstrOpcode::Nop:
            return true;
        case MicroInstrOpcode::LoadRegReg:
            return isNoOpLoadRegReg(inst, ops);
        case MicroInstrOpcode::LoadAddrRegMem:
            return isNoOpLoadAddrRegMem(inst, ops);
        case MicroInstrOpcode::LoadCondRegReg:
            return isNoOpLoadCondRegReg(inst, ops);
        case MicroInstrOpcode::OpBinaryRegReg:
            return isNoOpOpBinaryRegReg(inst, ops);
        case MicroInstrOpcode::OpBinaryRegImm:
            return isNoOpOpBinaryRegImm(inst, ops);
    }

    return false;
}

bool MicroOptimization::violatesEncoderConformance(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops)
{
    if (!context.encoder || !ops)
        return false;

    MicroConformanceIssue issue;
    return context.encoder->queryConformanceIssue(issue, inst, ops);
}

SWC_END_NAMESPACE();
