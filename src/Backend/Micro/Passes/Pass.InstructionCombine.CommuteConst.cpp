#include "pch.h"
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// Two-address lowering puts the left operand in the destination, so `2 * i`
// arrives with the constant where the immediate form cannot reach it:
//
//     LoadRegImm     t, 2                  LoadRegReg     t, i
//     OpBinaryRegReg t, i, mul      ->     OpBinaryRegImm t, 2, mul
//
// The operation is commutative, so putting the variable in the destination
// answers the same thing and leaves the constant where constant folding and
// strength reduction can see it — the multiply above ends up a shift, and the
// register pair the hardware multiply pins (rax/rdx on x86) is never claimed.
//
// The materializing instruction is rewritten in place rather than a copy being
// inserted, which keeps the instruction count identical until the passes that
// follow bring it down.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        bool isCommutativeIntOp(const MicroOp op)
        {
            switch (op)
            {
                case MicroOp::Add:
                case MicroOp::And:
                case MicroOp::MultiplySigned:
                case MicroOp::MultiplyUnsigned:
                case MicroOp::Or:
                case MicroOp::Xor:
                    return true;
                default:
                    return false;
            }
        }

        // Whether `reg` reaches `atRef` from a scalar float literal, which
        // legalization lowers to a constant-pool read.
        bool isScalarFloatLiteralReg(const Context& ctx, const MicroReg reg, const MicroInstrRef atRef)
        {
            const MicroSsaState::ReachingDef def = ctx.ssa->reachingDef(reg, atRef);
            if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::LoadRegImm)
                return false;
            const MicroInstrOperand* ops = def.inst->ops(*ctx.operands);
            return ops && ops[0].reg == reg && (ops[1].opBits == MicroOpBits::B32 || ops[1].opBits == MicroOpBits::B64);
        }
    }

    bool tryFoldConstantLhs(Context& ctx, MicroInstrRef binRef, const MicroInstr& binInst)
    {
        if (ctx.isClaimed(binRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* binOps = binInst.ops(*ctx.operands);
        if (!binOps)
            return false;

        const MicroReg    dst     = binOps[0].reg;
        const MicroReg    src     = binOps[1].reg;
        const MicroOpBits opBits  = binOps[2].opBits;
        const MicroOp     microOp = binOps[3].microOp;

        if (!dst.isVirtualInt() || !src.isVirtualInt() || dst == src)
            return false;
        const bool negate = microOp == MicroOp::Subtract;
        if (!negate && !isCommutativeIntOp(microOp))
            return false;

        // The destination must arrive holding a constant this instruction is
        // the only reader of, otherwise its definition cannot be repurposed.
        const auto dstReach = ctx.ssa->reachingDef(dst, binRef);
        if (!dstReach.valid() || dstReach.isPhi || !dstReach.instRef.isValid())
            return false;

        const MicroInstr* immInst = ctx.storage->ptr(dstReach.instRef);
        if (!immInst || immInst->op != MicroInstrOpcode::LoadRegImm)
            return false;

        const MicroInstrOperand* immOps = immInst->ops(*ctx.operands);
        if (!immOps || immOps[0].reg != dst || immOps[2].hasWideImmediateValue())
            return false;
        if (negate && (immOps[2].valueU64 & getBitsMask(opBits)) != 0)
            return false;
        if (immOps[1].opBits != opBits)
            return false;
        if (ctx.ssa->transitiveInstructionUseCount(dstReach.valueId, 2) != 1)
            return false;

        // The copy that replaces the materialization reads `src` earlier than
        // the operation did, so `src` must already hold the same value there.
        const auto srcAtBin = ctx.ssa->reachingDef(src, binRef);
        const auto srcAtImm = ctx.ssa->reachingDef(src, dstReach.instRef);
        if (!srcAtBin.valid() || !srcAtImm.valid() || srcAtBin.valueId != srcAtImm.valueId)
            return false;

        if (!ctx.claimAll({binRef, dstReach.instRef}))
            return false;

        MicroInstrOperand copyOps[3];
        copyOps[0].reg    = dst;
        copyOps[1].reg    = src;
        copyOps[2].opBits = opBits;
        ctx.emitRewrite(dstReach.instRef, MicroInstrOpcode::LoadRegReg, copyOps);

        // NEG computes the same value and arithmetic flags as zero minus src.
        if (negate)
        {
            MicroInstrOperand unary[3];
            unary[0].reg     = dst;
            unary[1].opBits  = opBits;
            unary[2].microOp = MicroOp::Negate;
            ctx.emitRewrite(binRef, MicroInstrOpcode::OpUnaryReg, unary);
            return true;
        }

        MicroInstrOperand newOps[4];
        newOps[0].reg     = dst;
        newOps[1].opBits  = opBits;
        newOps[2].microOp = microOp;
        newOps[3].setImmediateValue(ApInt(immOps[2].valueU64 & getBitsMask(opBits), getNumBits(opBits)));
        ctx.emitRewrite(binRef, MicroInstrOpcode::OpBinaryRegImm, newOps);
        return true;
    }

    // The same idea for a three-operand float operation: a scalar literal on the
    // left cannot become the memory operand, because x86 reads its second source
    // from memory. Commuting puts the constant where the constant-pool fold can
    // reach it, so `4.0 * c` stops holding a register of its own.
    //
    //     LoadRegImm k, 4.0                     LoadRegImm k, 4.0
    //     OpBinaryRegRegReg d, k, c, fmul  ->   OpBinaryRegRegReg d, c, k, fmul
    bool tryCommuteFloatConstantLhs(Context& ctx, const MicroInstrRef binRef, const MicroInstr& binInst)
    {
        if (ctx.isClaimed(binRef) || !ctx.ssa || binInst.numOperands < 5)
            return false;

        const MicroInstrOperand* binOps = binInst.ops(*ctx.operands);
        if (!binOps)
            return false;

        const MicroOpBits bits = binOps[3].opBits;
        if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
            return false;

        switch (binOps[4].microOp)
        {
            case MicroOp::FloatAdd:
            case MicroOp::FloatMultiply:
            case MicroOp::FloatAnd:
            case MicroOp::FloatXor:
                break;
            default:
                return false;
        }

        const MicroReg left  = binOps[1].reg;
        const MicroReg right = binOps[2].reg;
        if (!left.isVirtualFloat() || !right.isVirtualFloat() || left == right)
            return false;
        if (!isScalarFloatLiteralReg(ctx, left, binRef) || isScalarFloatLiteralReg(ctx, right, binRef))
            return false;

        if (!ctx.claimAll({binRef}))
            return false;

        MicroInstrOperand newOps[5];
        std::ranges::copy(std::span{binOps, 5}, newOps);
        newOps[1].reg = right;
        newOps[2].reg = left;
        ctx.emitRewrite(binRef, MicroInstrOpcode::OpBinaryRegRegReg, std::span{newOps, 5});
        return true;
    }
}

SWC_END_NAMESPACE();
