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
}

SWC_END_NAMESPACE();
