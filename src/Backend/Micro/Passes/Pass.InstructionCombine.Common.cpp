#include "pch.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    //===-- Math / opcode helpers ------------------------------------------===//

    bool isSameOpBitsInt(MicroOpBits a, MicroOpBits b)
    {
        return a == b && a != MicroOpBits::Zero && a != MicroOpBits::B128;
    }

    bool isRightIdentity(MicroOp op, MicroOpBits opBits, uint64_t imm)
    {
        const uint64_t mask = getBitsMask(opBits);
        switch (op)
        {
            case MicroOp::Add:
            case MicroOp::Subtract:
            case MicroOp::Or:
            case MicroOp::Xor:
            case MicroOp::ShiftLeft:
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticRight:
            case MicroOp::ShiftArithmeticLeft:
            case MicroOp::RotateLeft:
            case MicroOp::RotateRight:
                return (imm & mask) == 0;

            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
                return (imm & mask) == 1;

            case MicroOp::And:
                return (imm & mask) == mask;

            default:
                return false;
        }
    }

    bool isRightAbsorbing(MicroOp op, MicroOpBits opBits, uint64_t imm, uint64_t& outResult)
    {
        const uint64_t mask = getBitsMask(opBits);
        switch (op)
        {
            case MicroOp::And:
                if ((imm & mask) == 0)
                {
                    outResult = 0;
                    return true;
                }
                break;

            case MicroOp::Or:
                if ((imm & mask) == mask)
                {
                    outResult = mask;
                    return true;
                }
                break;

            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
                if ((imm & mask) == 0)
                {
                    outResult = 0;
                    return true;
                }
                break;

            default:
                break;
        }

        return false;
    }

    bool tryReassociate(MicroOp firstOp, uint64_t firstImm, MicroOp secondOp, uint64_t secondImm, MicroOpBits opBits, MicroOp& outOp, uint64_t& outImm)
    {
        return MicroPassHelpers::tryReassociateBinaryImmediate(firstOp, firstImm, secondOp, secondImm, opBits, outOp, outImm);
    }

    bool isMemFoldableOp(MicroOp op)
    {
        switch (op)
        {
            case MicroOp::Add:
            case MicroOp::Subtract:
            case MicroOp::And:
            case MicroOp::Or:
            case MicroOp::Xor:
            case MicroOp::ShiftLeft:
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticRight:
                return true;
            default:
                return false;
        }
    }

    bool isControlOrCall(const MicroInstr& inst)
    {
        const auto& info = MicroInstr::info(inst.op);
        return info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
               info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
               info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
               inst.op == MicroInstrOpcode::Label;
    }

    bool writesMemory(const MicroInstr& inst)
    {
        return MicroInstr::info(inst.op).flags.has(MicroInstrFlagsE::WritesMemory);
    }

    MicroOpBits useReadBits(const MicroInstr& useInst, const MicroInstrOperand* useOps, MicroReg reg)
    {
        if (!useOps)
            return MicroOpBits::Zero;

        switch (useInst.op)
        {
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadMemReg:
            case MicroInstrOpcode::CmpRegReg:
                return useOps[2].opBits;

            case MicroInstrOpcode::CmpRegImm:
            case MicroInstrOpcode::OpBinaryRegImm:
                return useOps[1].opBits;

            case MicroInstrOpcode::OpBinaryRegReg:
                return useOps[2].opBits;

            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
                return useOps[1].reg == reg ? useOps[3].opBits : MicroOpBits::Zero;

            default:
                return MicroOpBits::Zero;
        }
    }

    bool valueHasSingleUse(const MicroSsaState& ssa, MicroReg reg, MicroInstrRef defInstRef)
    {
        uint32_t valueId = 0;
        if (!ssa.defValue(reg, defInstRef, valueId))
            return false;
        const auto* info = ssa.valueInfo(valueId);
        return info && info->uses.size() == 1;
    }

    //===-- Context methods -------------------------------------------------===//

    bool Context::claimAll(std::initializer_list<MicroInstrRef> refs, bool allowRelocated)
    {
        for (const MicroInstrRef ref : refs)
            if (isClaimed(ref) || (!allowRelocated && isRelocated(ref)))
                return false;
        for (const MicroInstrRef ref : refs)
            claimed.insert(ref.get());
        return true;
    }
}

SWC_END_NAMESPACE();
