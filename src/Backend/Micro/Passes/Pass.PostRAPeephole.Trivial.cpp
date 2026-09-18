#include "pch.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
{
    namespace
    {
        uint32_t countLabelReferences(const Context& ctx, const uint64_t labelId)
        {
            uint32_t count = 0;
            for (const MicroInstr& candidate : ctx.storage->view())
            {
                const MicroInstrOperand* ops = candidate.ops(*ctx.operands);
                if (!ops)
                    continue;

                if ((candidate.op == MicroInstrOpcode::JumpCond || candidate.op == MicroInstrOpcode::JumpCondImm) &&
                    candidate.numOperands >= 3)
                    count += ops[2].valueU64 == labelId;
                else if (candidate.op == MicroInstrOpcode::JumpReg && candidate.numOperands >= 2)
                {
                    for (uint8_t index = 1; index < candidate.numOperands; ++index)
                        count += ops[index].valueU64 == labelId;
                }
                else if (candidate.op == MicroInstrOpcode::JumpTableData)
                {
                    for (uint8_t index = 0; index < candidate.numOperands; ++index)
                        count += ops[index].valueU64 == labelId;
                }
            }
            return count;
        }
    }

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

    // A conditional jump over an unconditional one:
    //
    //     jbe .L ; jmp .M ; .L:    ->    ja .M ; .L:
    //
    // Branch simplification does it before allocation; copies that vanish
    // after it can leave the shape behind, as a float clamp's did. Every
    // condition has an exact complement over the flags, unordered floats
    // included.
    bool tryInvertBranchOverJump(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || inst.op != MicroInstrOpcode::JumpCond || ops[0].cpuCond == MicroCond::Unconditional)
            return false;
        MicroCond inverted = MicroCond::Unconditional;
        if (!MicroPassHelpers::invertCondition(inverted, ops[0].cpuCond))
            return false;

        const MicroInstrRef      skipRef  = ctx.nextRef(ref);
        const MicroInstr*        skip     = ctx.instruction(skipRef);
        const MicroInstrOperand* skipOps  = skip ? skip->ops(*ctx.operands) : nullptr;
        if (!skipOps || skip->op != MicroInstrOpcode::JumpCond || skipOps[0].cpuCond != MicroCond::Unconditional)
            return false;
        const MicroInstrRef      labelRef = ctx.nextRef(skipRef);
        const MicroInstr*        label    = ctx.instruction(labelRef);
        const MicroInstrOperand* labelOps = label ? label->ops(*ctx.operands) : nullptr;
        if (!labelOps || label->op != MicroInstrOpcode::Label || labelOps[0].valueU64 != ops[2].valueU64 || !ctx.claimAll({ref, skipRef}))
            return false;

        MicroInstrOperand branch[3] = {ops[0], ops[1], ops[2]};
        branch[0].cpuCond           = inverted;
        branch[1].opBits            = MicroOpBits::B32;
        branch[2].valueU64          = skipOps[2].valueU64;
        ctx.emitRewrite(ref, MicroInstrOpcode::JumpCond, branch);
        ctx.emitErase(skipRef);
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

    // A scalar float conditional starts with copies for both arms and joins in
    // a third register. When the true value already occupies the ABI return
    // register, branch around one direct false-value copy instead. The same
    // return diamond around a float comparison can become MINSS/MAXSS directly.
    bool tryFoldFloatReturnSelectDiamond(Context& ctx, const MicroInstrRef firstCopyRef, const MicroInstr& firstCopyInst)
    {
        if (ctx.isClaimed(firstCopyRef) || firstCopyInst.op != MicroInstrOpcode::LoadRegReg ||
            !ctx.passContext || !ctx.passContext->usesFloatReturnRegOnRet)
            return false;

        std::array<MicroInstrRef, 9> refs;
        refs[0] = firstCopyRef;
        for (size_t index = 1; index < refs.size(); ++index)
        {
            refs[index] = ctx.nextRef(refs[index - 1]);
            if (!refs[index].isValid())
                return false;
        }

        constexpr std::array expected = {
            MicroInstrOpcode::LoadRegReg,
            MicroInstrOpcode::LoadRegReg,
            MicroInstrOpcode::Nop,
            MicroInstrOpcode::JumpCond,
            MicroInstrOpcode::JumpCond,
            MicroInstrOpcode::Label,
            MicroInstrOpcode::LoadRegReg,
            MicroInstrOpcode::Label,
            MicroInstrOpcode::LoadRegReg,
        };
        std::array<const MicroInstrOperand*, refs.size()> ops;
        for (size_t index = 0; index < refs.size(); ++index)
        {
            const MicroInstr* candidate = ctx.instruction(refs[index]);
            if (!candidate || ctx.isClaimed(refs[index]) ||
                (index == 2 ? candidate->op != MicroInstrOpcode::CmpRegImm && candidate->op != MicroInstrOpcode::CmpRegReg : candidate->op != expected[index]))
                return false;
            ops[index] = candidate->ops(*ctx.operands);
            if (!ops[index])
                return false;
        }

        const MicroInstrRef retRef = ctx.nextRef(refs.back());
        const MicroInstr*   ret    = ctx.instruction(retRef);
        if (!ret || ret->op != MicroInstrOpcode::Ret)
            return false;

        const MicroOpBits bits      = ops[0][2].opBits;
        const MicroReg    falseTmp  = ops[0][0].reg;
        const MicroReg    falseSrc  = ops[0][1].reg;
        const MicroReg    resultTmp = ops[1][0].reg;
        const MicroReg    trueSrc   = ops[1][1].reg;
        if ((bits != MicroOpBits::B32 && bits != MicroOpBits::B64) ||
            !falseTmp.isFloat() || !falseSrc.isFloat() || !resultTmp.isFloat() ||
            trueSrc != ctx.floatReturn || ops[1][2].opBits != bits ||
            ops[6][0].reg != resultTmp || ops[6][1].reg != falseTmp || ops[6][2].opBits != bits ||
            ops[8][0].reg != ctx.floatReturn || ops[8][1].reg != resultTmp || ops[8][2].opBits != bits)
            return false;

        const uint64_t falseLabelId = ops[5][0].valueU64;
        const uint64_t doneLabelId  = ops[7][0].valueU64;
        if (ops[3][0].cpuCond == MicroCond::Unconditional || ops[3][2].valueU64 != falseLabelId ||
            ops[4][0].cpuCond != MicroCond::Unconditional || ops[4][2].valueU64 != doneLabelId ||
            countLabelReferences(ctx, falseLabelId) != 1 || countLabelReferences(ctx, doneLabelId) != 1)
            return false;

        const MicroInstr* compare = ctx.instruction(refs[2]);
        SWC_ASSERT(compare);
        if (compare->op == MicroInstrOpcode::CmpRegReg)
        {
            const bool isMin = ops[2][0].reg == falseTmp && ops[2][1].reg == resultTmp;
            const bool isMax = ops[2][0].reg == resultTmp && ops[2][1].reg == falseTmp;
            if (ops[2][2].opBits != bits || ops[3][0].cpuCond != MicroCond::BelowOrEqual || (!isMin && !isMax))
                return false;

            std::array<MicroInstrOperand, 4> minMax = {};
            minMax[0].reg                           = ctx.floatReturn;
            minMax[1].reg                           = falseSrc;
            minMax[2].opBits                        = bits;
            minMax[3].microOp                       = isMin ? MicroOp::FloatMin : MicroOp::FloatMax;
            if (!ctx.claimAll({refs[0], refs[1], refs[2], refs[3], refs[4], refs[6], refs[8]}))
                return false;
            ctx.emitRewrite(refs[0], MicroInstrOpcode::OpBinaryRegReg, minMax);
            ctx.emitErase(refs[1]);
            ctx.emitErase(refs[2]);
            ctx.emitErase(refs[3]);
            ctx.emitErase(refs[4]);
            ctx.emitErase(refs[6]);
            ctx.emitErase(refs[8]);
            return true;
        }

        MicroCond inverted = MicroCond::Unconditional;
        if (!MicroPassHelpers::invertCondition(inverted, ops[3][0].cpuCond))
            return false;

        std::array<MicroInstrOperand, 3> branch = {ops[3][0], ops[3][1], ops[3][2]};
        branch[0].cpuCond  = inverted;
        branch[2].valueU64 = doneLabelId;
        std::array<MicroInstrOperand, 3> falseCopy = {ops[6][0], ops[6][1], ops[6][2]};
        falseCopy[0].reg = ctx.floatReturn;
        falseCopy[1].reg = falseSrc;
        falseCopy[2].opBits = MicroOpBits::B128;

        if (!ctx.claimAll({refs[0], refs[1], refs[3], refs[4], refs[6], refs[8]}))
            return false;
        ctx.emitErase(refs[0]);
        ctx.emitErase(refs[1]);
        ctx.emitRewrite(refs[3], MicroInstrOpcode::JumpCond, branch);
        ctx.emitErase(refs[4]);
        ctx.emitRewrite(refs[6], MicroInstrOpcode::LoadRegReg, falseCopy);
        ctx.emitErase(refs[8]);
        return true;
    }
}

SWC_END_NAMESPACE();
