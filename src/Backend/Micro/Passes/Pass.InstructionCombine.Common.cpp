#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Backend/Micro/MicroPassHelpers.h"

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

    namespace
    {
        bool tryFoldAddSub(MicroOp     firstOp,
                           uint64_t    firstImm,
                           MicroOp     secondOp,
                           uint64_t    secondImm,
                           MicroOpBits opBits,
                           MicroOp&    outOp,
                           uint64_t&   outImm)
        {
            const uint64_t mask        = getBitsMask(opBits);
            const uint64_t a           = firstImm & mask;
            const uint64_t b           = secondImm & mask;
            const bool     firstIsSub  = firstOp == MicroOp::Subtract;
            const bool     secondIsSub = secondOp == MicroOp::Subtract;

            uint64_t addImm = 0;
            if (firstIsSub == secondIsSub)
                addImm = firstIsSub ? ((0u - (a + b)) & mask) : ((a + b) & mask);
            else if (firstIsSub)
                addImm = (b - a) & mask;
            else
                addImm = (a - b) & mask;

            const uint64_t subImm = (0u - addImm) & mask;
            if (addImm <= subImm)
            {
                outOp  = MicroOp::Add;
                outImm = addImm;
            }
            else
            {
                outOp  = MicroOp::Subtract;
                outImm = subImm;
            }
            return true;
        }

        bool foldSameBitwise(MicroOp     op,
                             uint64_t    lhs,
                             uint64_t    rhs,
                             MicroOpBits opBits,
                             uint64_t&   outImm)
        {
            uint64_t   value  = 0;
            const auto status = MicroPassHelpers::foldBinaryImmediate(value, lhs, rhs, op, opBits);
            if (status != Math::FoldStatus::Ok)
                return false;
            outImm = value & getBitsMask(opBits);
            return true;
        }
    }

    bool tryReassociate(MicroOp     firstOp,
                        uint64_t    firstImm,
                        MicroOp     secondOp,
                        uint64_t    secondImm,
                        MicroOpBits opBits,
                        MicroOp&    outOp,
                        uint64_t&   outImm)
    {
        const bool firstIsAddSub  = firstOp == MicroOp::Add || firstOp == MicroOp::Subtract;
        const bool secondIsAddSub = secondOp == MicroOp::Add || secondOp == MicroOp::Subtract;
        if (firstIsAddSub && secondIsAddSub)
            return tryFoldAddSub(firstOp, firstImm, secondOp, secondImm, opBits, outOp, outImm);

        if (firstOp != secondOp)
            return false;

        switch (firstOp)
        {
            case MicroOp::And:
            case MicroOp::Or:
            case MicroOp::Xor:
            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
                outOp = firstOp;
                return foldSameBitwise(firstOp, firstImm, secondImm, opBits, outImm);

            case MicroOp::ShiftLeft:
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticRight:
            {
                const uint64_t sum = firstImm + secondImm;
                if (sum >= getNumBits(opBits))
                    return false;
                outOp  = firstOp;
                outImm = sum;
                return true;
            }

            default:
                return false;
        }
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

    //===-- Context methods -------------------------------------------------===//

    bool Context::isClaimed(MicroInstrRef ref) const
    {
        return claimed.contains(ref.get());
    }

    bool Context::claimAll(std::initializer_list<MicroInstrRef> refs)
    {
        for (const MicroInstrRef ref : refs)
            if (isClaimed(ref))
                return false;
        for (const MicroInstrRef ref : refs)
            claimed.insert(ref.get());
        return true;
    }

    void Context::emitErase(MicroInstrRef ref)
    {
        Action a;
        a.ref   = ref;
        a.erase = true;
        actions.push_back(a);
    }

    void Context::emitRewrite(MicroInstrRef                      ref,
                              MicroInstrOpcode                   newOp,
                              std::span<const MicroInstrOperand> newOps,
                              bool                               allocNewBlock)
    {
        SWC_ASSERT(newOps.size() <= Action::K_MAX_OPS);
        Action a;
        a.ref      = ref;
        a.newOp    = newOp;
        a.numOps   = static_cast<uint8_t>(newOps.size());
        a.allocOps = allocNewBlock;
        for (size_t i = 0; i < newOps.size(); ++i)
            a.ops[i] = newOps[i];
        actions.push_back(a);
    }

    //===-- Action application ---------------------------------------------===//

    void applyAction(Context& ctx, const Action& action)
    {
        SWC_ASSERT(ctx.storage);
        SWC_ASSERT(ctx.operands);

        if (action.erase)
        {
            ctx.storage->erase(action.ref);
            return;
        }

        MicroInstr* inst = ctx.storage->ptr(action.ref);
        SWC_ASSERT(inst);

        if (action.allocOps)
        {
            const auto [newRef, opsBlock] = ctx.operands->emplaceUninitArray(action.numOps);
            for (uint8_t i = 0; i < action.numOps; ++i)
                opsBlock[i] = action.ops[i];
            inst->opsRef = newRef;
        }
        else if (action.numOps > 0)
        {
            MicroInstrOperand* existing = inst->ops(*ctx.operands);
            SWC_ASSERT(existing);
            for (uint8_t i = 0; i < action.numOps; ++i)
                existing[i] = action.ops[i];
        }

        inst->op          = action.newOp;
        inst->numOperands = action.numOps;
    }

    //===-- Registry --------------------------------------------------------===//

    void PatternRegistry::add(MicroInstrOpcode op, PatternFn fn)
    {
        byOpcode[static_cast<size_t>(op)].push_back(fn);
    }

    std::span<PatternFn const> PatternRegistry::patternsFor(MicroInstrOpcode op) const
    {
        return byOpcode[static_cast<size_t>(op)].span();
    }
}

SWC_END_NAMESPACE();
