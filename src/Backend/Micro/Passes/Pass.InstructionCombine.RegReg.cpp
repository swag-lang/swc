#include "pch.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// OpBinaryRegReg combiner: idempotent self-ops (v op v).

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        constexpr uint32_t K_MAX_INPLACE_WINDOW = 32;

        bool isInPlaceBinaryOp(MicroInstrOpcode op)
        {
            return op == MicroInstrOpcode::OpBinaryRegReg ||
                   op == MicroInstrOpcode::OpBinaryRegImm ||
                   op == MicroInstrOpcode::OpBinaryRegMem;
        }

        bool isBlockBoundary(const MicroInstr& inst)
        {
            const MicroInstrDef& info = MicroInstr::info(inst.op);
            return inst.op == MicroInstrOpcode::Label ||
                   info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                   info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                   info.flags.has(MicroInstrFlagsE::IsCallInstruction);
        }

        // (a & b) ^ (a & c) = a & (b ^ c). Keep the two non-common
        // inputs at their original read positions and move only the common
        // input, after proving that its value survives to the final operation.
        bool tryFactorXorOfAnds(Context& ctx, MicroInstrRef ref, const MicroInstrOperand* ops)
        {
            if (!ctx.ssa || ops[3].microOp != MicroOp::Xor || !ops[1].reg.isVirtualInt())
                return false;
            const MicroOpBits bits = ops[2].opBits;
            if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
                return false;

            std::array    regs{ops[0].reg, ops[1].reg};
            std::array    defs{ctx.ssa->reachingDef(regs[0], ref), ctx.ssa->reachingDef(regs[1], ref)};
            MicroInstrRef lhsCopy = MicroInstrRef::invalid();
            if (defs[0].valid() && !defs[0].isPhi && defs[0].inst && defs[0].inst->op == MicroInstrOpcode::LoadRegReg)
            {
                const MicroInstrOperand* copied = defs[0].inst->ops(*ctx.operands);
                if (!copied || copied[2].opBits != bits || !copied[1].reg.isVirtualInt() ||
                    !valueHasSingleUse(*ctx.ssa, regs[0], defs[0].instRef))
                    return false;
                lhsCopy = defs[0].instRef;
                regs[0] = copied[1].reg;
                defs[0] = ctx.ssa->reachingDef(regs[0], lhsCopy);
            }
            if (regs[0] == regs[1])
                return false;
            std::array<MicroSsaState::ReachingDef, 2> initial;
            std::array<const MicroInstrOperand*, 2>   andOps;
            std::array<const MicroInstrOperand*, 2>   copyOps;
            for (uint32_t i = 0; i < 2; ++i)
            {
                if (!defs[i].valid() || defs[i].isPhi || !defs[i].inst || defs[i].inst->op != MicroInstrOpcode::OpBinaryRegReg)
                    return false;
                andOps[i] = defs[i].inst->ops(*ctx.operands);
                if (!andOps[i] || andOps[i][2].opBits != bits || andOps[i][3].microOp != MicroOp::And ||
                    !valueHasSingleUse(*ctx.ssa, regs[i], defs[i].instRef))
                    return false;
                initial[i] = ctx.ssa->reachingDef(regs[i], defs[i].instRef);
                if (!initial[i].valid() || initial[i].isPhi || !initial[i].inst || initial[i].inst->op != MicroInstrOpcode::LoadRegReg)
                    return false;
                copyOps[i] = initial[i].inst->ops(*ctx.operands);
                if (!copyOps[i] || copyOps[i][2].opBits != bits || !copyOps[i][1].reg.isVirtualInt() ||
                    andOps[i][1].reg == regs[0] || andOps[i][1].reg == regs[1] || andOps[i][1].reg == ops[0].reg)
                    return false;
                if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, defs[i].instRef))
                    return false;
            }

            const MicroReg common = copyOps[0][1].reg;
            if (common != copyOps[1][1].reg || common == regs[0] || common == regs[1] || common == ops[0].reg)
                return false;
            const auto commonValue = ctx.ssa->reachingDef(common, initial[0].instRef);
            if (!commonValue.valid() || ctx.ssa->reachingDef(common, initial[1].instRef).valueId != commonValue.valueId ||
                ctx.ssa->reachingDef(common, ref).valueId != commonValue.valueId)
                return false;

            bool          seenSecond = false;
            MicroInstrRef cursor     = defs[0].instRef;
            for (uint32_t step = 0; step < K_MAX_INPLACE_WINDOW && cursor.isValid() && cursor != ref; ++step)
            {
                const MicroInstr* current = ctx.storage->ptr(cursor);
                if (!current || isBlockBoundary(*current))
                    return false;
                seenSecond |= cursor == defs[1].instRef;
                if (cursor == lhsCopy && !seenSecond)
                    return false;
                cursor = ctx.storage->findNextInstructionRef(cursor);
            }
            if (cursor != ref || !seenSecond || !ctx.claimAll({ref, defs[0].instRef, defs[1].instRef, initial[0].instRef, initial[1].instRef, lhsCopy.isValid() ? lhsCopy : ref}))
                return false;

            MicroInstrOperand first[3];
            first[0].reg    = regs[0];
            first[1].reg    = andOps[0][1].reg;
            first[2].opBits = bits;
            ctx.emitRewrite(defs[0].instRef, MicroInstrOpcode::LoadRegReg, first);

            MicroInstrOperand factored[4];
            factored[0].reg     = regs[0];
            factored[1].reg     = andOps[1][1].reg;
            factored[2].opBits  = bits;
            factored[3].microOp = MicroOp::Xor;
            ctx.emitRewrite(defs[1].instRef, MicroInstrOpcode::OpBinaryRegReg, factored);
            factored[0].reg     = ops[0].reg;
            factored[1].reg     = common;
            factored[3].microOp = MicroOp::And;
            ctx.emitRewrite(ref, MicroInstrOpcode::OpBinaryRegReg, factored);
            return true;
        }
    }

    // Collapse the in-place-update copy round-trip that `acc op= x` lowers to once
    // mem2reg has promoted `acc` to a (loop-carried) virtual register:
    //
    //     T = A          (LoadRegReg, T a fresh temp, A the accumulator)
    //     T = T op C     (the anchored in-place op; C may be reg/imm/mem)
    //     A = T          (LoadRegReg, write the result back to A)
    //   ->
    //     A = A op C
    //
    // T only mirrors A across the update, so operating in place on A is identical
    // and removes a two-move recurrence on the loop's critical path. Copy
    // elimination cannot do this: it forwards *uses* of a copy, but the op's
    // destination is a use+def it must skip, and A is a preserved/loop-carried
    // value it must not rewrite. This changes only how A is defined and leaves its
    // observed value unchanged. Operates on virtual registers (unique temps), so
    // there is no physical-register-reuse hazard. Uses transitive-instruction-use
    // counts (not raw use-list sizes) so dead loop-header phis don't hide the
    // single-consumer shape.
    bool tryFuseInPlaceUpdate(Context& ctx, MicroInstrRef opRef, const MicroInstr& opInst)
    {
        if (ctx.isClaimed(opRef) || !ctx.ssa)
            return false;
        if (!isInPlaceBinaryOp(opInst.op))
            return false;

        const MicroInstrOperand* ops = opInst.ops(*ctx.operands);
        if (!ops)
            return false;

        const MicroReg t = ops[0].reg;
        if (!t.isVirtualInt())
            return false;

        // The op must update t in place: t is read and written and is its only
        // def. A source operand equal to t would dangle once the init copy is
        // erased, so reject those.
        const MicroInstrUseDef opUseDef = opInst.collectUseDef(*ctx.operands, nullptr);
        if (opUseDef.defs.size() != 1 || opUseDef.defs[0] != t || !microRegSpanContains(opUseDef.uses, t))
            return false;
        if ((opInst.op == MicroInstrOpcode::OpBinaryRegReg || opInst.op == MicroInstrOpcode::OpBinaryRegMem) && ops[1].reg == t)
            return false;

        // The value t holds entering the op must come from `t = A`, consumed only
        // by this op.
        const auto reachT = ctx.ssa->reachingDef(t, opRef);
        if (!reachT.valid() || reachT.isPhi)
            return false;
        const MicroInstrRef initRef  = reachT.instRef;
        const MicroInstr*   initInst = ctx.storage->ptr(initRef);
        if (!initInst || initInst->op != MicroInstrOpcode::LoadRegReg)
            return false;
        const MicroInstrOperand* initOps = initInst->ops(*ctx.operands);
        if (!initOps || initOps[0].reg != t)
            return false;
        const MicroReg a = initOps[1].reg;
        if (!a.isVirtualInt() || a == t)
            return false;
        if (singleDirectInstructionUse(*ctx.ssa, reachT.valueId) != opRef)
            return false;

        // The op's result must be consumed only by the writeback `A = t`.
        uint32_t resultValueId = 0;
        if (!ctx.ssa->defValue(t, opRef, resultValueId))
            return false;
        const MicroInstrRef writebackRef = singleDirectInstructionUse(*ctx.ssa, resultValueId);
        if (!writebackRef.isValid())
            return false;
        const MicroInstr* wbInst = ctx.storage->ptr(writebackRef);
        if (!wbInst || wbInst->op != MicroInstrOpcode::LoadRegReg)
            return false;
        const MicroInstrOperand* wbOps = wbInst->ops(*ctx.operands);
        if (!wbOps || wbOps[1].reg != t || wbOps[0].reg != a)
            return false;

        // A must hold the same value at the init, the op (which will now read it),
        // and the writeback: it must not be redefined across the region.
        const auto reachAInit = ctx.ssa->reachingDef(a, initRef);
        if (!reachAInit.valid() ||
            ctx.ssa->reachingDef(a, opRef).valueId != reachAInit.valueId ||
            ctx.ssa->reachingDef(a, writebackRef).valueId != reachAInit.valueId)
            return false;

        // Confine init/op/writeback to one basic block and confirm A is not read
        // between the op and the writeback — the rewrite defines A at the op's
        // position, earlier than the original writeback, so an intervening reader
        // of A would otherwise observe the new value instead of the old one.
        const auto view  = ctx.storage->view();
        const auto endIt = view.end();
        auto       it    = view.begin();
        while (it != endIt && it.current != initRef)
            ++it;
        if (it == endIt)
            return false;

        bool seenOp    = false;
        bool reachedWb = false;
        for (uint32_t step = 0; step < K_MAX_INPLACE_WINDOW && it != endIt; ++step, ++it)
        {
            const MicroInstrRef cur = it.current;
            if (cur == writebackRef)
            {
                reachedWb = true;
                break;
            }
            const MicroInstr& w = *it;
            if (cur != initRef && cur != opRef && isBlockBoundary(w))
                return false;
            if (seenOp && cur != opRef)
            {
                const MicroInstrUseDef ud = w.collectUseDef(*ctx.operands, nullptr);
                if (microRegSpanContains(ud.uses, a))
                    return false;
            }
            if (cur == opRef)
                seenOp = true;
        }
        if (!reachedWb || !seenOp)
            return false;

        if (!ctx.claimAll({initRef, opRef, writebackRef}))
            return false;

        MicroInstrOperand newOps[Action::K_MAX_OPS] = {};
        const uint8_t     numOps                    = opInst.numOperands;
        if (numOps > Action::K_MAX_OPS)
            return false;
        for (uint8_t i = 0; i < numOps; ++i)
            newOps[i] = ops[i];
        newOps[0].reg = a;

        ctx.emitRewrite(opRef, opInst.op, std::span<const MicroInstrOperand>(newOps, numOps));
        ctx.emitErase(initRef);
        ctx.emitErase(writebackRef);
        return true;
    }

    bool tryOpBinaryRegReg(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[0].reg.isVirtualInt())
            return false;
        if (ops[0].reg != ops[1].reg)
            return tryFactorXorOfAnds(ctx, ref, ops);

        const MicroReg    dst    = ops[0].reg;
        const MicroOpBits opBits = ops[2].opBits;
        const MicroOp     op     = ops[3].microOp;

        switch (op)
        {
            case MicroOp::And:
            case MicroOp::Or:
                // v op v == v. Rewriting to a self-copy buys nothing pre-RA,
                // so only drop when the result is unused afterward.
                if (ctx.ssa && !ctx.ssa->isRegUsedAfter(dst, ref))
                {
                    if (!ctx.claimAll({ref}))
                        return false;
                    ctx.emitErase(ref);
                    return true;
                }
                return false;

            case MicroOp::Subtract:
            case MicroOp::Xor:
            {
                if (!ctx.claimAll({ref}))
                    return false;
                MicroInstrOperand clearOps[2];
                clearOps[0].reg    = dst;
                clearOps[1].opBits = opBits;
                ctx.emitRewrite(ref, MicroInstrOpcode::ClearReg, clearOps);
                return true;
            }

            default:
                return false;
        }
    }

    // A shift of a value that is still needed afterwards:
    //
    //     copy d, s; d <<= c      ->      d = s << c
    //
    // The machine has a shift that names its source, its count and its result
    // separately, and takes the count from any register. Written the other
    // way it costs the copy above, and a move of the count into the one
    // register the legacy form reads it from. It writes no flags, so it only
    // stands where nothing reads them after the shift.
    bool tryThreeOperandShift(Context& ctx, const MicroInstrRef ref, const MicroInstr& inst)
    {
        if (!ctx.ssa || ctx.isClaimed(ref) || ctx.isRelocated(ref))
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops)
            return false;

        // ops: [0] dst (read and written), [1] count, [2] opBits, [3] microOp
        const MicroOp op = ops[3].microOp;
        if (op != MicroOp::ShiftLeft && op != MicroOp::ShiftRight && op != MicroOp::ShiftArithmeticRight && op != MicroOp::ShiftArithmeticLeft)
            return false;
        if (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64)
            return false;

        const MicroReg dst   = ops[0].reg;
        const MicroReg count = ops[1].reg;
        if (!dst.isVirtualInt() || !count.isVirtualInt() || dst == count)
            return false;

        // The copy that put the value where the shift could destroy it.
        const auto reaching = ctx.ssa->reachingDef(dst, ref);
        if (!reaching.valid() || reaching.isPhi || !reaching.inst)
            return false;
        if (reaching.inst->op != MicroInstrOpcode::LoadRegReg)
            return false;

        const MicroInstrOperand* copyOps = reaching.inst->ops(*ctx.operands);
        if (!copyOps || copyOps[0].reg != dst || copyOps[2].opBits != ops[2].opBits)
            return false;

        const MicroReg src = copyOps[1].reg;
        if (!src.isVirtualInt() || src == count || src == dst)
            return false;
        if (!valueHasSingleUse(*ctx.ssa, dst, reaching.instRef))
            return false;

        // The legacy shift writes the flags and this form does not.
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref))
            return false;

        if (!ctx.claimAll({ref, reaching.instRef}))
            return false;

        MicroInstrOperand newOps[5] = {};
        newOps[0].reg    = dst;
        newOps[1].reg    = src;
        newOps[2].reg    = count;
        newOps[3].opBits = ops[2].opBits;
        newOps[4].microOp = op;
        ctx.emitRewrite(ref, MicroInstrOpcode::OpBinaryRegRegReg, std::span<const MicroInstrOperand>(newOps, 5), true);
        ctx.emitErase(reaching.instRef);
        return true;
    }
}

SWC_END_NAMESPACE();
