#include "pch.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
{
    bool tryEraseTrivial(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!isTriviallyErasableNoEffect(inst, ops) &&
            !isRedundantFallthroughJumpToNextLabel(ctx, ref, inst, ops))
            return false;

        if (!ctx.claimAll({ref}))
            return false;

        ctx.emitErase(ref);
        return true;
    }

    // `mov eax, eax` clears the upper half of rax, so a dword self-copy is
    // kept as a rule. Where that half is already clear on every path - after
    // any 32-bit write - it changes nothing.
    bool tryEraseZeroExtendedSelfCopy(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || inst.op != MicroInstrOpcode::LoadRegReg || ops[0].reg != ops[1].reg || !ops[0].reg.isInt() ||
            ops[2].opBits != MicroOpBits::B32)
            return false;
        if (!ctx.isUpperHalfZeroBefore(ref, ops[0].reg) || !ctx.claimAll({ref}))
            return false;
        ctx.emitErase(ref);
        return true;
    }

    // A float clear is kept as a rule: it zeroes the lanes a partial write
    // such as cvtsi2ss leaves alone. When the next instruction replaces the
    // whole register instead - another clear, a scalar load from memory, a
    // move from an integer register - the clear does nothing:
    //
    //     xorps xmm0, xmm0 ; movss xmm0, [rip + c]    ->    movss xmm0, [rip + c]
    //
    // A float constant materialized over a conversion kept the clear that
    // conversion needed. The rule anchors on the write, after the folds that
    // consume it along with its clear.
    bool tryEraseFloatClearBeforeFullWrite(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[0].reg.isFloat())
            return false;
        const MicroReg reg = ops[0].reg;

        switch (inst.op)
        {
            case MicroInstrOpcode::ClearReg:
                break;
            case MicroInstrOpcode::LoadRegMem:
                if (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64)
                    return false;
                break;
            case MicroInstrOpcode::LoadRegReg:
                if (!ops[1].reg.isInt())
                    return false;
                break;
            default:
                return false;
        }

        const MicroInstrRef      clearRef = ctx.previousRef(ref);
        const MicroInstr*        clear    = ctx.instruction(clearRef);
        const MicroInstrOperand* clearOps = clear ? clear->ops(*ctx.operands) : nullptr;
        if (!clearOps || clear->op != MicroInstrOpcode::ClearReg || clearOps[0].reg != reg || !ctx.claimAll({clearRef, ref}))
            return false;
        ctx.emitErase(clearRef);
        return true;
    }
}

SWC_END_NAMESPACE();
