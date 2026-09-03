#include "pch.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// Zero-extensions of values that are already zero-extended.
//
// A 32-bit integer write clears the upper half of its 64-bit register
// (MicroInstr.h states the contract). The lowering widens every `u32` it adds
// in 64 bits with an explicit `zero_extend b64 <- b32`, so a word loaded from
// memory and promoted for a 64-bit addition costs a load and a `mov r32, r32`
// that changes nothing, and masking the sum back with `& 0xFFFFFFFF` costs
// another where a 32-bit addition would have produced the masked value
// directly. ChaCha20's key-stream loop spent six of its twenty-five
// instructions that way.
//
// Two rules, both anchored on the extend:
//
//     zero_extend d, s, b64 <- b32          s defined by a 32-bit write
//   ->
//     d = s (b64)
//
//     op s, x, b64 ; zero_extend d, s, b64 <- b32
//   ->
//     op s, x, b32 ; d = s (b64)
//
// The second needs the operation's result read by the extend alone, and its
// low 32 bits to depend only on the low 32 bits of its inputs.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        constexpr uint32_t K_MAX_PHI_DEPTH = 8;

        // Binary operations whose low 32 result bits are a function of their
        // operands' low 32 bits, so a 32-bit mask over the 64-bit result is
        // the 32-bit operation itself. Shifts are out: a 64-bit count reaches
        // bit 63 where a 32-bit one is masked to five bits.
        bool lowBitsDependOnLowBits(const MicroOp op)
        {
            switch (op)
            {
                case MicroOp::Add:
                case MicroOp::Subtract:
                case MicroOp::And:
                case MicroOp::Or:
                case MicroOp::Xor:
                case MicroOp::MultiplySigned:
                    return true;
                default:
                    return false;
            }
        }

        // Integer operations whose 32-bit form writes its whole destination.
        // The bit scans do not: they leave the destination untouched on a
        // zero source.
        bool writesWholeRegisterAt32(const MicroOp op)
        {
            switch (op)
            {
                case MicroOp::Add:
                case MicroOp::Subtract:
                case MicroOp::And:
                case MicroOp::Or:
                case MicroOp::Xor:
                case MicroOp::MultiplySigned:
                case MicroOp::MultiplyUnsigned:
                case MicroOp::DivideSigned:
                case MicroOp::DivideUnsigned:
                case MicroOp::ModuloSigned:
                case MicroOp::ModuloUnsigned:
                case MicroOp::ShiftLeft:
                case MicroOp::ShiftArithmeticLeft:
                case MicroOp::ShiftRight:
                case MicroOp::ShiftArithmeticRight:
                case MicroOp::RotateLeft:
                case MicroOp::RotateRight:
                case MicroOp::Negate:
                case MicroOp::BitwiseNot:
                case MicroOp::ByteSwap:
                case MicroOp::PopCount:
                    return true;
                default:
                    return false;
            }
        }

        bool extendLeavesUpperHalfZero(const MicroOpBits dstBits, const MicroOpBits srcBits)
        {
            if (dstBits == MicroOpBits::B32)
                return true;
            return dstBits == MicroOpBits::B64 && getNumBits(srcBits) <= 32;
        }

        // Whether the instruction defines `reg` with its upper 32 bits zero: a
        // 32-bit integer write, or a widening whose source is at most 32 bits.
        bool definesZeroExtended32(const MicroInstr& inst, const MicroInstrOperand* ops, const MicroReg reg)
        {
            if (!ops || ops[0].reg != reg)
                return false;

            switch (inst.op)
            {
                case MicroInstrOpcode::ClearReg:
                    return true;
                case MicroInstrOpcode::LoadRegImm:
                    return ops[1].opBits == MicroOpBits::B32;
                case MicroInstrOpcode::LoadRegReg:
                case MicroInstrOpcode::LoadRegMem:
                    return ops[2].opBits == MicroOpBits::B32;
                case MicroInstrOpcode::LoadCondRegReg:
                case MicroInstrOpcode::LoadAmcRegMem:
                    return ops[3].opBits == MicroOpBits::B32;
                case MicroInstrOpcode::LoadZeroExtRegReg:
                case MicroInstrOpcode::LoadZeroExtRegMem:
                    return extendLeavesUpperHalfZero(ops[2].opBits, ops[3].opBits);
                case MicroInstrOpcode::LoadZeroExtAmcRegMem:
                    return extendLeavesUpperHalfZero(ops[3].opBits, ops[4].opBits);
                case MicroInstrOpcode::LoadSignedExtRegReg:
                case MicroInstrOpcode::LoadSignedExtRegMem:
                    return ops[2].opBits == MicroOpBits::B32;
                case MicroInstrOpcode::OpBinaryRegReg:
                case MicroInstrOpcode::OpBinaryRegMem:
                    return ops[2].opBits == MicroOpBits::B32 && writesWholeRegisterAt32(ops[3].microOp);
                case MicroInstrOpcode::OpBinaryRegImm:
                case MicroInstrOpcode::OpUnaryReg:
                    return ops[1].opBits == MicroOpBits::B32 && writesWholeRegisterAt32(ops[2].microOp);
                default:
                    return false;
            }
        }

        // A value is zero-extended when its definition is, or when every input
        // of the phi that merges it is. A phi met again on the way is the
        // loop-carried copy of the value being decided, which its other inputs
        // settle.
        bool valueIsZeroExtended32(const Context& ctx, const uint32_t valueId, SmallVector<uint32_t>& visited, const uint32_t depth)
        {
            const MicroSsaState::ValueInfo* value = ctx.ssa->valueInfo(valueId);
            if (!value)
                return false;

            if (value->isPhi())
            {
                if (depth >= K_MAX_PHI_DEPTH)
                    return false;
                if (std::ranges::find(visited, valueId) != visited.end())
                    return true;
                visited.push_back(valueId);

                const MicroSsaState::PhiInfo* phi = ctx.ssa->phiInfo(value->phiIndex);
                if (!phi || phi->incomingValueIds.empty())
                    return false;
                for (const uint32_t incoming : phi->incomingValueIds)
                {
                    if (!valueIsZeroExtended32(ctx, incoming, visited, depth + 1))
                        return false;
                }
                return true;
            }

            const MicroInstr* inst = ctx.storage->ptr(value->instRef);
            return inst && definesZeroExtended32(*inst, inst->ops(*ctx.operands), value->reg);
        }

        bool isDwordToQwordExtend(const MicroInstrOperand* ops)
        {
            return ops &&
                   ops[0].reg.isVirtualInt() &&
                   ops[1].reg.isVirtualInt() &&
                   ops[2].opBits == MicroOpBits::B64 &&
                   ops[3].opBits == MicroOpBits::B32;
        }

        void emitExtendAsCopy(Context& ctx, const MicroInstrRef ref, const MicroReg dst, const MicroReg src)
        {
            if (dst == src)
            {
                ctx.emitErase(ref);
                return;
            }

            MicroInstrOperand moveOps[3];
            moveOps[0].reg    = dst;
            moveOps[1].reg    = src;
            moveOps[2].opBits = MicroOpBits::B64;
            ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegReg, moveOps);
        }
    }

    bool tryDropRedundantZeroExtend(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!isDwordToQwordExtend(ops))
            return false;

        const MicroReg dst = ops[0].reg;
        const MicroReg src = ops[1].reg;

        const MicroSsaState::ReachingDef reaching = ctx.ssa->reachingDef(src, ref);
        if (!reaching.valid())
            return false;

        SmallVector<uint32_t> visited;
        if (!valueIsZeroExtended32(ctx, reaching.valueId, visited, 0))
            return false;

        if (!ctx.claimAll({ref}))
            return false;

        emitExtendAsCopy(ctx, ref, dst, src);
        return true;
    }

    bool tryNarrowMaskedArithmetic(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!isDwordToQwordExtend(ops))
            return false;

        const MicroReg dst = ops[0].reg;
        const MicroReg src = ops[1].reg;

        const MicroSsaState::ReachingDef reaching = ctx.ssa->reachingDef(src, ref);
        if (!reaching.valid() || reaching.isPhi || !reaching.inst || ctx.isClaimed(reaching.instRef))
            return false;

        const MicroInstr&        def    = *reaching.inst;
        const MicroInstrOperand* defOps = def.ops(*ctx.operands);
        if (!defOps || defOps[0].reg != src)
            return false;

        // A memory operand narrows with the operation: the low four bytes of
        // the word are the low 32 bits of the value.
        uint8_t bitsSlot = 0;
        uint8_t immSlot  = 0;
        MicroOp op       = MicroOp::Add;
        switch (def.op)
        {
            case MicroInstrOpcode::OpBinaryRegReg:
            case MicroInstrOpcode::OpBinaryRegMem:
                bitsSlot = 2;
                op       = defOps[3].microOp;
                break;
            case MicroInstrOpcode::OpBinaryRegImm:
                bitsSlot = 1;
                immSlot  = 3;
                op       = defOps[2].microOp;
                break;
            default:
                return false;
        }

        if (defOps[bitsSlot].opBits != MicroOpBits::B64 || !lowBitsDependOnLowBits(op))
            return false;

        // Every other reader of the result wants its upper half.
        if (singleDirectInstructionUse(*ctx.ssa, reaching.valueId) != ref)
            return false;

        // The narrower operation sets the flags at 32 bits.
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, reaching.instRef))
            return false;

        if (!ctx.claimAll({reaching.instRef, ref}))
            return false;

        MicroInstrOperand narrowOps[Action::K_MAX_OPS] = {};
        for (uint8_t i = 0; i < def.numOperands; ++i)
            narrowOps[i] = defOps[i];
        narrowOps[bitsSlot].opBits = MicroOpBits::B32;
        if (immSlot)
            narrowOps[immSlot].valueU64 &= 0xFFFFFFFFu;
        ctx.emitRewrite(reaching.instRef, def.op, std::span{narrowOps, def.numOperands});

        emitExtendAsCopy(ctx, ref, dst, src);
        return true;
    }
}

SWC_END_NAMESPACE();
