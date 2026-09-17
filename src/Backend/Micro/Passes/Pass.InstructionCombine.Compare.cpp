#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Backend/Micro/MicroPassHelpers.h"

// Compares: flags an earlier instruction already produced reused instead of
// computed again, and known values folded into the compared operand.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    // `a > b ? a - b : b - a` computes `a - b` before the compare that the
    // select reads, and a subtraction sets the flags of that very compare:
    //
    //     T = a; T -= b                      U = b; U -= a
    //     U = b; U -= a              ->      T = a; T -= b
    //     cmp a, b                           cmovbe T, U
    //     cmovbe T, U
    //
    // Moving the subtraction next to the reader drops the compare, as LLVM's
    // x86 lowering reuses the flags of a `sub` for its `cmp`. Nothing between
    // may read T or the flags, and a and b must hold the same values at both
    // places.
    bool tryReuseSubtractionFlags(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        constexpr uint32_t K_MAX_WINDOW = 6;

        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops   = inst.ops(*ctx.operands);
        const MicroReg           left  = ops[0].reg;
        const MicroReg           right = ops[1].reg;
        const MicroOpBits        bits  = ops[2].opBits;
        if (!left.isVirtualInt() || !right.isVirtualInt() || left == right || getNumBits(bits) < 32)
            return false;

        // The reader right after the compare, and nothing after it that reads
        // the flags a subtraction would leave different.
        const MicroInstrRef readerRef = ctx.storage->findNextInstructionRef(ref);
        const MicroInstr*   reader    = readerRef.isValid() ? ctx.storage->ptr(readerRef) : nullptr;
        if (!reader || (reader->op != MicroInstrOpcode::LoadCondRegReg && reader->op != MicroInstrOpcode::SetCondReg && reader->op != MicroInstrOpcode::JumpCond))
            return false;

        // Walk back to `sub T, right` whose T held `left`.
        SmallVector<MicroInstrRef, 8> between;
        MicroInstrRef                 subRef = ctx.storage->findPreviousInstructionRef(ref);
        for (uint32_t step = 0; step < K_MAX_WINDOW && subRef.isValid(); ++step)
        {
            const MicroInstr* candidate = ctx.storage->ptr(subRef);
            if (!candidate)
                return false;
            const MicroInstrOperand* candidateOps = candidate->ops(*ctx.operands);
            if (candidate->op == MicroInstrOpcode::OpBinaryRegReg && candidateOps[3].microOp == MicroOp::Subtract &&
                candidateOps[1].reg == right && candidateOps[2].opBits == bits && candidateOps[0].reg.isVirtualInt() &&
                candidateOps[0].reg != left && candidateOps[0].reg != right)
                break;
            if (candidate->op == MicroInstrOpcode::Label || MicroPassHelpers::instructionActuallyUsesCpuFlags(*candidate, candidateOps))
                return false;
            const MicroInstrFlags flags = MicroInstr::info(candidate->op).flags;
            if (flags.has(MicroInstrFlagsE::JumpInstruction) || flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;
            between.push_back(subRef);
            subRef = ctx.storage->findPreviousInstructionRef(subRef);
        }
        if (!subRef.isValid() || between.size() >= K_MAX_WINDOW || ctx.isClaimed(subRef))
            return false;

        const MicroInstr*        sub    = ctx.storage->ptr(subRef);
        const MicroInstrOperand* subOps = sub->ops(*ctx.operands);
        if (sub->op != MicroInstrOpcode::OpBinaryRegReg || subOps[3].microOp != MicroOp::Subtract || subOps[1].reg != right)
            return false;
        const MicroReg result = subOps[0].reg;

        // T = left right before the subtraction.
        const MicroInstrRef copyRef = ctx.storage->findPreviousInstructionRef(subRef);
        const MicroInstr*   copy    = copyRef.isValid() ? ctx.storage->ptr(copyRef) : nullptr;
        if (!copy || copy->op != MicroInstrOpcode::LoadRegReg || ctx.isClaimed(copyRef))
            return false;
        const MicroInstrOperand* copyOps = copy->ops(*ctx.operands);
        if (copyOps[0].reg != result || copyOps[1].reg != left || getNumBits(copyOps[2].opBits) < getNumBits(bits))
            return false;

        // left and right keep their values, and the moved pair's register is
        // not touched in between.
        const auto sameValue = [&](MicroReg reg, MicroInstrRef earlier) {
            const MicroSsaState::ReachingDef before = ctx.ssa->reachingDef(reg, earlier);
            const MicroSsaState::ReachingDef after  = ctx.ssa->reachingDef(reg, ref);
            return before.valid() && after.valid() && before.valueId == after.valueId;
        };
        if (!sameValue(left, copyRef) || !sameValue(right, subRef))
            return false;
        // Copies of T move along with it; nothing else in between may mention
        // T or those copies.
        SmallVector<MicroInstrRef, 4>        followers;
        SmallVector<MicroReg, 4>             followerRegs;
        SmallVector<MicroInstrRegOperandRef> regOperands;
        for (const MicroInstrRef betweenRef : between)
        {
            const MicroInstr*        betweenInst = ctx.storage->ptr(betweenRef);
            const MicroInstrOperand* betweenOps  = betweenInst->ops(*ctx.operands);
            if (betweenInst->op == MicroInstrOpcode::LoadRegReg && betweenOps[1].reg == result && betweenOps[0].reg.isVirtualInt() &&
                betweenOps[0].reg != left && betweenOps[0].reg != right && getNumBits(betweenOps[2].opBits) >= getNumBits(bits) &&
                !ctx.isClaimed(betweenRef))
            {
                followers.push_back(betweenRef);
                followerRegs.push_back(betweenOps[0].reg);
            }
        }
        for (const MicroInstrRef betweenRef : between)
        {
            if (std::ranges::find(followers, betweenRef) != followers.end())
                continue;
            const MicroInstr* betweenInst = ctx.storage->ptr(betweenRef);
            regOperands.clear();
            betweenInst->collectRegOperands(*ctx.operands, regOperands, nullptr);
            for (const MicroInstrRegOperandRef& regOperand : regOperands)
            {
                if (regOperand.reg && (*regOperand.reg == result || std::ranges::find(followerRegs, *regOperand.reg) != followerRegs.end()))
                    return false;
            }
        }

        if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, readerRef, ctx.builder))
            return false;
        if (!ctx.claimAll({ref, subRef, copyRef, readerRef}))
            return false;

        MicroInstrOperand movedCopy[3];
        for (size_t i = 0; i < 3; ++i)
            movedCopy[i] = copyOps[i];
        MicroInstrOperand movedSub[4];
        for (size_t i = 0; i < 4; ++i)
            movedSub[i] = subOps[i];
        for (const MicroInstrRef followerRef : followers)
        {
            if (!ctx.claimAll({followerRef}))
                return false;
        }

        ctx.emitErase(copyRef);
        ctx.emitErase(subRef);
        ctx.emitInsertBefore(ref, MicroInstrOpcode::LoadRegReg, movedCopy);
        ctx.emitInsertBefore(ref, MicroInstrOpcode::OpBinaryRegReg, movedSub);
        // `between` runs backwards: the copies go back in their order.
        for (auto it = followers.rbegin(); it != followers.rend(); ++it)
        {
            const MicroInstrOperand* followerOps = ctx.storage->ptr(*it)->ops(*ctx.operands);
            MicroInstrOperand        movedFollower[3];
            for (size_t i = 0; i < 3; ++i)
                movedFollower[i] = followerOps[i];
            ctx.emitInsertBefore(ref, MicroInstrOpcode::LoadRegReg, movedFollower);
            ctx.emitErase(*it);
        }
        ctx.emitErase(ref);
        return true;
    }
}

SWC_END_NAMESPACE();
