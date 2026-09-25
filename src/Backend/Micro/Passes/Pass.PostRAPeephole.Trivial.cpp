#include "pch.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
{
    namespace
    {
        bool labelsHaveSingleReference(const Context& ctx, const uint64_t firstLabelId, const uint64_t secondLabelId)
        {
            uint32_t firstCount  = 0;
            uint32_t secondCount = 0;
            for (const MicroInstr& candidate : ctx.storage->view())
            {
                if (candidate.op != MicroInstrOpcode::JumpCond && candidate.op != MicroInstrOpcode::JumpCondImm &&
                    candidate.op != MicroInstrOpcode::JumpReg && candidate.op != MicroInstrOpcode::JumpTableData)
                    continue;
                const MicroInstrOperand* ops = candidate.ops(*ctx.operands);
                if (!ops)
                    continue;

                if ((candidate.op == MicroInstrOpcode::JumpCond || candidate.op == MicroInstrOpcode::JumpCondImm) &&
                    candidate.numOperands >= 3)
                {
                    firstCount += ops[2].valueU64 == firstLabelId;
                    secondCount += ops[2].valueU64 == secondLabelId;
                }
                else if (candidate.op == MicroInstrOpcode::JumpReg && candidate.numOperands >= 2)
                {
                    for (uint8_t index = 1; index < candidate.numOperands; ++index)
                    {
                        firstCount += ops[index].valueU64 == firstLabelId;
                        secondCount += ops[index].valueU64 == secondLabelId;
                    }
                }
                else if (candidate.op == MicroInstrOpcode::JumpTableData)
                {
                    for (uint8_t index = 0; index < candidate.numOperands; ++index)
                    {
                        firstCount += ops[index].valueU64 == firstLabelId;
                        secondCount += ops[index].valueU64 == secondLabelId;
                    }
                }
                if (firstCount > 1 || secondCount > 1)
                    return false;
            }
            return firstCount == 1 && secondCount == 1;
        }
    }

    bool tryEraseTrivial(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const MicroInstrOperand* ops = inst.op == MicroInstrOpcode::Nop ? nullptr : inst.ops(*ctx.operands);
        if (!isTriviallyErasableNoEffect(inst, ops) &&
            !isRedundantFallthroughJumpToNextLabel(ctx, ref, inst, ops))
            return false;

        if (!ctx.claimAll({ref}))
            return false;

        ctx.emitErase(ref);
        return true;
    }

    // Register allocation may leave a load/add/store for a loop-local field
    // that pre-RA combine deliberately kept scalar. Once the assigned result
    // register is dead, an x64 memory increment avoids both the reload and
    // the store without changing register allocation or the add's flags.
    bool tryFoldDeadScalarIncrement(Context& ctx, const MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        const MicroInstrOperand* load = loadInst.ops(*ctx.operands);
        if (!load || !load[0].reg.isInt() || !load[1].reg.isInt() || load[0].reg == load[1].reg)
            return false;

        const MicroInstrRef addRef = ctx.nextRef(loadRef);
        const MicroInstr* addInst = ctx.instruction(addRef);
        const MicroInstrOperand* add = addInst && addInst->op == MicroInstrOpcode::OpBinaryRegImm ? addInst->ops(*ctx.operands) : nullptr;
        if (!add || add[0].reg != load[0].reg || add[1].opBits != load[2].opBits ||
            add[2].microOp != MicroOp::Add || add[3].hasWideImmediateValue() || add[3].valueU64 != 1)
            return false;

        const MicroInstrRef storeRef = ctx.nextRef(addRef);
        const MicroInstr* storeInst = ctx.instruction(storeRef);
        const MicroInstrOperand* store = storeInst && storeInst->op == MicroInstrOpcode::LoadMemReg ? storeInst->ops(*ctx.operands) : nullptr;
        if (!store || store[0].reg != load[1].reg || store[1].reg != load[0].reg ||
            store[2].opBits != load[2].opBits || store[3].valueU64 != load[3].valueU64 ||
            !ctx.isRegDeadAfter(load[0].reg, ctx.instructionIndex + 2))
            return false;

        MicroInstrOperand folded[5];
        folded[0].reg = load[1].reg;
        folded[1].opBits = load[2].opBits;
        folded[2].microOp = MicroOp::Add;
        folded[3].valueU64 = load[3].valueU64;
        folded[4].valueU64 = 1;
        MicroInstr probe;
        probe.op = MicroInstrOpcode::OpBinaryMemImm;
        probe.numOperands = 5;
        MicroConformanceIssue issue;
        if ((ctx.encoder && ctx.encoder->queryConformanceIssue(issue, probe, folded)) ||
            !ctx.claimAll({loadRef, addRef, storeRef}))
            return false;

        ctx.emitRewrite(addRef, probe.op, folded, true);
        ctx.emitErase(loadRef);
        ctx.emitErase(storeRef);
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
        if (!ops || ops[0].cpuCond == MicroCond::Unconditional)
            return false;
        MicroCond inverted = MicroCond::Unconditional;
        if (!MicroPassHelpers::invertCondition(inverted, ops[0].cpuCond))
            return false;

        const MicroInstrRef      skipRef  = ctx.nextRef(ref);
        const MicroInstr*        skip     = ctx.instruction(skipRef);
        const MicroInstrOperand* skipOps  = skip && skip->op == MicroInstrOpcode::JumpCond ?
            skip->ops(*ctx.operands) : nullptr;
        if (!skipOps || skipOps[0].cpuCond != MicroCond::Unconditional)
            return false;
        const MicroInstrRef      labelRef = ctx.nextRef(skipRef);
        const MicroInstr*        label    = ctx.instruction(labelRef);
        const MicroInstrOperand* labelOps = label && label->op == MicroInstrOpcode::Label ?
            label->ops(*ctx.operands) : nullptr;
        if (!labelOps || labelOps[0].valueU64 != ops[2].valueU64 || !ctx.claimAll({ref, skipRef}))
            return false;

        MicroInstrOperand branch[3] = {ops[0], ops[1], ops[2]};
        branch[0].cpuCond           = inverted;
        branch[1].opBits            = MicroOpBits::B32;
        branch[2].valueU64          = skipOps[2].valueU64;
        ctx.emitRewrite(ref, MicroInstrOpcode::JumpCond, branch);
        ctx.emitErase(skipRef);
        return true;
    }

    namespace
    {
        constexpr uint32_t K_MAX_RETURN_TAIL = 16;

        bool collectSimpleReturnTail(const Context& ctx, MicroInstrRef ref,
                                     std::array<MicroInstrRef, K_MAX_RETURN_TAIL>& refs, uint32_t& count)
        {
            count = 0;
            const MicroInstr* inst = ctx.instruction(ref);
            if (inst && inst->op == MicroInstrOpcode::LoadRegReg)
            {
                refs[count++] = ref;
                ref = ctx.nextRef(ref);
                inst = ctx.instruction(ref);
            }
            if (inst && inst->op == MicroInstrOpcode::OpBinaryRegImm)
            {
                const MicroInstrOperand* ops = inst->ops(*ctx.operands);
                if (!ops || ops[0].reg != ctx.stackPointer || ops[1].opBits != MicroOpBits::B64 ||
                    ops[2].microOp != MicroOp::Add)
                    return false;
                refs[count++] = ref;
                ref = ctx.nextRef(ref);
                inst = ctx.instruction(ref);
            }
            while (inst && inst->op == MicroInstrOpcode::Pop && count + 1 < K_MAX_RETURN_TAIL)
            {
                refs[count++] = ref;
                ref = ctx.nextRef(ref);
                inst = ctx.instruction(ref);
            }
            if (!inst || inst->op != MicroInstrOpcode::Ret || count >= K_MAX_RETURN_TAIL)
                return false;
            refs[count++] = ref;
            return true;
        }

        bool sameReturnInstruction(const Context& ctx, const MicroInstrRef lhsRef, const MicroInstrRef rhsRef)
        {
            const MicroInstr* lhs = ctx.instruction(lhsRef);
            const MicroInstr* rhs = ctx.instruction(rhsRef);
            if (!lhs || !rhs || lhs->op != rhs->op || lhs->numOperands != rhs->numOperands)
                return false;
            const MicroInstrOperand* a = lhs->ops(*ctx.operands);
            const MicroInstrOperand* b = rhs->ops(*ctx.operands);
            switch (lhs->op)
            {
                case MicroInstrOpcode::LoadRegReg:
                    return a && b && a[0].reg == b[0].reg && a[1].reg == b[1].reg && a[2].opBits == b[2].opBits;
                case MicroInstrOpcode::OpBinaryRegImm:
                    return a && b && a[0].reg == b[0].reg && a[1].opBits == b[1].opBits &&
                           a[2].microOp == b[2].microOp &&
                           a[3].valueInt.bitWidth() == b[3].valueInt.bitWidth() && a[3].valueInt.eq(b[3].valueInt);
                case MicroInstrOpcode::Pop:
                    return a && b && a[0].reg == b[0].reg;
                case MicroInstrOpcode::Ret:
                    return true;
                default:
                    return false;
            }
        }
    }

    // Two identical return tails can share one epilogue while the branch to
    // the collision path becomes the complementary branch to the later tail.
    // The collision path then becomes the fallthrough, as in a single-exit
    // lookup loop, without adding a jump to either hot path.
    bool tryShareReturnEpilogue(Context& ctx, const MicroInstrRef branchRef, const MicroInstr& branchInst)
    {
        const MicroInstrOperand* branchOps = branchInst.ops(*ctx.operands);
        if (!branchOps || branchOps[0].cpuCond == MicroCond::Unconditional)
            return false;
        MicroCond inverted = MicroCond::Unconditional;
        if (!MicroPassHelpers::invertCondition(inverted, branchOps[0].cpuCond))
            return false;

        std::array<MicroInstrRef, K_MAX_RETURN_TAIL> firstTail;
        uint32_t firstCount = 0;
        if (!collectSimpleReturnTail(ctx, ctx.nextRef(branchRef), firstTail, firstCount))
            return false;
        const MicroInstrRef collisionRef = ctx.nextRef(firstTail[firstCount - 1]);
        const MicroInstr* collision = ctx.instruction(collisionRef);
        const MicroInstrOperand* collisionOps = collision ? collision->ops(*ctx.operands) : nullptr;
        if (!collision || collision->op != MicroInstrOpcode::Label || !collisionOps ||
            collisionOps[0].valueU64 != branchOps[2].valueU64)
            return false;

        MicroInstrRef exitRef = ctx.nextRef(collisionRef);
        for (uint32_t step = 0; step < 12; ++step)
        {
            const MicroInstr* inst = ctx.instruction(exitRef);
            if (!inst || inst->op == MicroInstrOpcode::Ret)
                return false;
            if (inst->op == MicroInstrOpcode::Label)
                break;
            exitRef = ctx.nextRef(exitRef);
        }
        const MicroInstr* exitLabel = ctx.instruction(exitRef);
        const MicroInstrOperand* exitOps = exitLabel ? exitLabel->ops(*ctx.operands) : nullptr;
        if (!exitLabel || exitLabel->op != MicroInstrOpcode::Label || !exitOps)
            return false;

        std::array<MicroInstrRef, K_MAX_RETURN_TAIL> secondTail;
        uint32_t secondCount = 0;
        if (!collectSimpleReturnTail(ctx, ctx.nextRef(exitRef), secondTail, secondCount) ||
            firstCount != secondCount)
            return false;
        for (uint32_t i = 0; i < firstCount; ++i)
            if (!sameReturnInstruction(ctx, firstTail[i], secondTail[i]))
                return false;

        std::array<MicroInstrRef, K_MAX_RETURN_TAIL + 1> claims;
        claims[0] = branchRef;
        for (uint32_t i = 0; i < firstCount; ++i)
            claims[i + 1] = firstTail[i];
        if (!ctx.claimAll(std::span{claims.data(), firstCount + 1}))
            return false;

        MicroInstrOperand rewritten[3] = {branchOps[0], branchOps[1], branchOps[2]};
        rewritten[0].cpuCond = inverted;
        rewritten[2].valueU64 = exitOps[0].valueU64;
        ctx.emitRewrite(branchRef, MicroInstrOpcode::JumpCond, rewritten);
        for (uint32_t i = 0; i < firstCount; ++i)
            ctx.emitErase(firstTail[i]);
        return true;
    }

    // `mov eax, eax` clears the upper half of rax, so a dword self-copy is
    // kept as a rule. Where that half is already clear on every path - after
    // any 32-bit write - it changes nothing.
    bool tryEraseZeroExtendedSelfCopy(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || ops[0].reg != ops[1].reg || !ops[0].reg.isInt() ||
            ops[2].opBits != MicroOpBits::B32)
            return false;
        if (!ctx.isUpperHalfZeroBefore(ref, ops[0].reg) || !ctx.claimAll({ref}))
            return false;
        ctx.emitErase(ref);
        return true;
    }

    // A zero-extended byte remains zero above bit seven after an 8-bit
    // subtract: x86 changes only the low byte. A delimiter check may branch
    // away, but its fall-through still comes from the zero-extending load.
    //
    //   movzx r, byte [p]; cmp r, ','; je exit; sub r8, '0'; movzx r, r8
    //       ->
    //   movzx r, byte [p]; cmp r, ','; je exit; sub r8, '0'
    bool tryEraseByteZeroExtendAfterSubtract(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* loadOps = inst.ops(*ctx.operands);
        const uint32_t destBitsIndex = inst.op == MicroInstrOpcode::LoadZeroExtAmcRegMem ? 3 : 2;
        const uint32_t sourceBitsIndex = inst.op == MicroInstrOpcode::LoadZeroExtAmcRegMem ? 4 : 3;
        if (!loadOps || !loadOps[0].reg.isInt() ||
            (loadOps[destBitsIndex].opBits != MicroOpBits::B32 && loadOps[destBitsIndex].opBits != MicroOpBits::B64) ||
            loadOps[sourceBitsIndex].opBits != MicroOpBits::B8)
            return false;
        const MicroReg reg = loadOps[0].reg;
        const MicroInstrRef cmpRef = ctx.nextRef(ref);
        const MicroInstrRef branchRef = ctx.nextRef(cmpRef);
        MicroInstrRef subRef = ctx.nextRef(branchRef);
        const MicroInstr* beforeSub = ctx.instruction(subRef);
        MicroInstrRef addressRef = MicroInstrRef::invalid();
        // The decimal accumulator may prepare its LEA between the delimiter
        // branch and the byte subtraction. It cannot change this byte value.
        if (beforeSub &&
            (beforeSub->op == MicroInstrOpcode::LoadAddrRegMem ||
             beforeSub->op == MicroInstrOpcode::LoadAddrAmcRegMem))
        {
            const MicroInstrUseDef useDef = beforeSub->collectUseDef(*ctx.operands, ctx.encoder);
            if (std::ranges::find(useDef.uses, reg) != useDef.uses.end() ||
                std::ranges::find(useDef.defs, reg) != useDef.defs.end())
                return false;
            addressRef = subRef;
            subRef = ctx.nextRef(subRef);
        }
        const MicroInstrRef extRef = ctx.nextRef(subRef);
        const MicroInstr* sub = ctx.instruction(subRef);
        const MicroInstr* branch = ctx.instruction(branchRef);
        const MicroInstr* cmp = ctx.instruction(cmpRef);
        const MicroInstr* ext = ctx.instruction(extRef);
        if (!sub || !branch || !cmp || !ext ||
            sub->op != MicroInstrOpcode::OpBinaryRegImm || branch->op != MicroInstrOpcode::JumpCond ||
            cmp->op != MicroInstrOpcode::CmpRegImm ||
            ext->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const auto* subOps = sub->ops(*ctx.operands);
        const auto* branchOps = branch->ops(*ctx.operands);
        const auto* cmpOps = cmp->ops(*ctx.operands);
        const auto* extOps = ext->ops(*ctx.operands);
        if (!subOps || !branchOps || !cmpOps || !extOps ||
            subOps[0].reg != reg || subOps[1].opBits != MicroOpBits::B8 || subOps[2].microOp != MicroOp::Subtract ||
            branchOps[0].cpuCond == MicroCond::Unconditional || cmpOps[0].reg != reg ||
            (cmpOps[1].opBits != MicroOpBits::B32 && cmpOps[1].opBits != MicroOpBits::B64) ||
            extOps[0].reg != reg || extOps[1].reg != reg ||
            extOps[2].opBits != MicroOpBits::B64 || extOps[3].opBits != MicroOpBits::B8)
            return false;
        const bool claimed = addressRef.isValid() ?
            ctx.claimAll({ref, cmpRef, branchRef, addressRef, subRef, extRef}) :
            ctx.claimAll({ref, cmpRef, branchRef, subRef, extRef});
        if (!claimed)
            return false;
        ctx.emitErase(extRef);
        return true;
    }

    // Move a byte's zero extension into its memory load when the only work
    // before the original extension is a low-byte subtraction. The subtraction
    // leaves the high bits established by MOVZX intact, so the final MOVZX is
    // redundant even when the byte subtraction wraps.
    bool tryFoldByteLoadSubtractExtend(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* load = inst.ops(*ctx.operands);
        if (!load || inst.numOperands < 7 || load[3].opBits != MicroOpBits::B8 ||
            load[4].opBits != MicroOpBits::B64 || load[1].reg.isInstructionPointer())
            return false;
        const MicroReg reg = load[0].reg;
        if (!reg.isInt())
            return false;
        const MicroInstrRef subRef = ctx.nextRef(ref);
        const MicroInstrRef extRef = ctx.nextRef(subRef);
        const MicroInstr* sub = ctx.instruction(subRef);
        const MicroInstr* ext = ctx.instruction(extRef);
        if (!sub || !ext || sub->op != MicroInstrOpcode::OpBinaryRegImm ||
            ext->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const auto* subOps = sub->ops(*ctx.operands);
        const auto* extOps = ext->ops(*ctx.operands);
        if (!subOps || !extOps || subOps[0].reg != reg || subOps[1].opBits != MicroOpBits::B8 ||
            subOps[2].microOp != MicroOp::Subtract || extOps[0].reg != reg || extOps[1].reg != reg ||
            extOps[2].opBits != MicroOpBits::B64 || extOps[3].opBits != MicroOpBits::B8 ||
            !ctx.claimAll({ref, subRef, extRef}))
            return false;

        MicroInstrOperand widened[7] = {load[0], load[1], load[2], load[3], load[4], load[5], load[6]};
        widened[3].opBits = MicroOpBits::B64;
        widened[4].opBits = MicroOpBits::B8;
        ctx.emitRewrite(ref, MicroInstrOpcode::LoadZeroExtAmcRegMem, widened);
        ctx.emitErase(extRef);
        return true;
    }

    // A 32-bit comparison observes the same low bits before and after a
    // 32-to-64-bit sign extension. Read the original register when the wider
    // value has no later consumer.
    bool tryDropSignExtendBeforeNarrowCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const MicroInstrOperand* extend = inst.ops(*ctx.operands);
        if (!extend ||
            extend[2].opBits != MicroOpBits::B64 || extend[3].opBits != MicroOpBits::B32 ||
            !extend[0].reg.isInt() || !extend[1].reg.isInt())
            return false;

        const MicroInstrRef cmpRef = ctx.nextRef(ref);
        const MicroInstr*   cmp    = ctx.instruction(cmpRef);
        const auto*         cmpOps = cmp && cmp->op == MicroInstrOpcode::CmpRegImm ?
            cmp->ops(*ctx.operands) : nullptr;
        if (!cmpOps || cmpOps[0].reg != extend[0].reg ||
            cmpOps[1].opBits != MicroOpBits::B32)
            return false;

        bool deadAfterCompare = ctx.isRegDeadAfter(extend[0].reg, ctx.instructionIndex + 1);
        if (!deadAfterCompare)
        {
            // A large function may not have usable whole-function liveness.
            // Prove the two immediate branch paths locally when each path
            // overwrites the wider value before reading it.
            const MicroInstrRef branchRef = ctx.nextRef(cmpRef);
            const MicroInstr*   branch    = ctx.instruction(branchRef);
            const auto* branchOps = branch && branch->op == MicroInstrOpcode::JumpCond ?
                branch->ops(*ctx.operands) : nullptr;
            if (branchOps && branch->numOperands >= 3 &&
                branchOps[0].cpuCond != MicroCond::Unconditional &&
                regIsDeadAfter(ctx, branchRef, extend[0].reg))
            {
                for (auto it = ctx.storage->view().begin(), endIt = ctx.storage->view().end(); it != endIt; ++it)
                {
                    if (it->op != MicroInstrOpcode::Label)
                        continue;
                    const MicroInstrOperand* labelOps = it->ops(*ctx.operands);
                    if (labelOps && labelOps[0].valueU64 == branchOps[2].valueU64)
                    {
                        deadAfterCompare = regIsDeadAfter(ctx, it.current, extend[0].reg);
                        break;
                    }
                }
            }
        }
        if (!deadAfterCompare || !ctx.claimAll({ref, cmpRef}))
            return false;

        MicroInstrOperand narrowed[3] = {cmpOps[0], cmpOps[1], cmpOps[2]};
        narrowed[0].reg               = extend[1].reg;
        ctx.emitErase(ref);
        ctx.emitRewrite(cmpRef, cmp->op, narrowed);
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

    // A scalar float argument that arrives in the ABI return register can be
    // copied to a temporary only to receive a sign-mask XOR and be copied back
    // for return. Retarget the XOR to the ABI register: it still reads the
    // argument's original bits, and the two moves become dead.
    bool tryFoldFloatReturnXorCopyChain(Context& ctx, const MicroInstrRef firstCopyRef, const MicroInstr& firstCopyInst)
    {
        if (ctx.isClaimed(firstCopyRef) || !ctx.passContext || !ctx.passContext->usesFloatReturnRegOnRet)
            return false;

        const auto* firstCopy = firstCopyInst.ops(*ctx.operands);
        if (!firstCopy || !firstCopy[0].reg.isFloat() || firstCopy[1].reg != ctx.floatReturn ||
            (firstCopy[2].opBits != MicroOpBits::B32 && firstCopy[2].opBits != MicroOpBits::B64))
            return false;

        const MicroInstrRef xorRef      = ctx.nextRef(firstCopyRef);
        const MicroInstrRef lastCopyRef = ctx.nextRef(xorRef);
        const MicroInstrRef retRef      = ctx.nextRef(lastCopyRef);
        const MicroInstr*   xorInst     = ctx.instruction(xorRef);
        const MicroInstr*   lastCopyInst = ctx.instruction(lastCopyRef);
        const MicroInstr*   retInst     = ctx.instruction(retRef);
        const auto*         xorOps      = xorInst ? xorInst->ops(*ctx.operands) : nullptr;
        const auto*         lastCopy    = lastCopyInst ? lastCopyInst->ops(*ctx.operands) : nullptr;
        if (!xorInst || !lastCopyInst || !retInst || !xorOps || !lastCopy ||
            xorInst->op != MicroInstrOpcode::OpBinaryRegMem || xorOps[0].reg != firstCopy[0].reg ||
            xorOps[1].reg != MicroReg::instructionPointer() || xorOps[2].opBits != firstCopy[2].opBits ||
            xorOps[3].microOp != MicroOp::FloatXor || lastCopyInst->op != MicroInstrOpcode::LoadRegReg ||
            lastCopy[0].reg != ctx.floatReturn || lastCopy[1].reg != firstCopy[0].reg ||
            lastCopy[2].opBits != firstCopy[2].opBits || retInst->op != MicroInstrOpcode::Ret)
            return false;

        std::array<MicroInstrOperand, 5> rewrittenXor = {xorOps[0], xorOps[1], xorOps[2], xorOps[3], xorOps[4]};
        rewrittenXor[0].reg = ctx.floatReturn;
        if (!ctx.claimAll({firstCopyRef, xorRef, lastCopyRef}))
            return false;

        ctx.emitErase(firstCopyRef);
        ctx.emitRewrite(xorRef, xorInst->op, rewrittenXor);
        ctx.emitErase(lastCopyRef);
        return true;
    }

    // A scalar float conditional starts with copies for both arms and joins in
    // a third register. When the true value already occupies the ABI return
    // register, branch around one direct false-value copy instead. The same
    // return diamond around a float comparison can become MINSS/MAXSS directly.
    bool tryFoldFloatReturnSelectDiamond(Context& ctx, const MicroInstrRef firstCopyRef, const MicroInstr& firstCopyInst)
    {
        if (ctx.isClaimed(firstCopyRef) || !ctx.passContext || !ctx.passContext->usesFloatReturnRegOnRet)
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
            !labelsHaveSingleReference(ctx, falseLabelId, doneLabelId))
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
