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
    }

    bool tryCommuteConstantLhs(Context& ctx, MicroInstrRef binRef, const MicroInstr& binInst)
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
        if (!isCommutativeIntOp(microOp))
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
        if (immOps[1].opBits != opBits)
            return false;
        if (!valueHasSingleUse(*ctx.ssa, dst, dstReach.instRef))
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

        MicroInstrOperand newOps[4];
        newOps[0].reg     = dst;
        newOps[1].opBits  = opBits;
        newOps[2].microOp = microOp;
        newOps[3].setImmediateValue(ApInt(immOps[2].valueU64 & getBitsMask(opBits), getNumBits(opBits)));
        ctx.emitRewrite(binRef, MicroInstrOpcode::OpBinaryRegImm, newOps);
        return true;
    }
}

SWC_END_NAMESPACE();
