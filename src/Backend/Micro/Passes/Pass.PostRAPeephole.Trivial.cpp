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
    // such as cvtsi2ss leaves alone. The next instruction may instead replace
    // the whole register - another clear, a scalar load from memory, a move
    // from an integer register - and then the clear does nothing:
    //
    //     xorps xmm0, xmm0 ; movss xmm0, [rip + c]    ->    movss xmm0, [rip + c]
    //
    // A float constant materialized over a conversion kept the clear that
    // conversion needed.
    bool tryEraseFloatClearBeforeFullWrite(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || inst.op != MicroInstrOpcode::ClearReg || !ops[0].reg.isFloat())
            return false;
        const MicroReg reg = ops[0].reg;

        const MicroInstrRef      nextRef = ctx.nextRef(ref);
        const MicroInstr*        next    = ctx.instruction(nextRef);
        const MicroInstrOperand* nextOps = next ? next->ops(*ctx.operands) : nullptr;
        if (!nextOps || nextOps[0].reg != reg)
            return false;

        bool replacesWholeRegister = false;
        switch (next->op)
        {
            case MicroInstrOpcode::ClearReg:
                replacesWholeRegister = true;
                break;
            case MicroInstrOpcode::LoadRegMem:
                replacesWholeRegister = nextOps[2].opBits == MicroOpBits::B32 || nextOps[2].opBits == MicroOpBits::B64;
                break;
            case MicroInstrOpcode::LoadRegReg:
                replacesWholeRegister = nextOps[1].reg.isInt();
                break;
            default:
                break;
        }
        if (!replacesWholeRegister || !ctx.claimAll({ref, nextRef}))
            return false;
        ctx.emitErase(ref);
        return true;
    }
}

SWC_END_NAMESPACE();
