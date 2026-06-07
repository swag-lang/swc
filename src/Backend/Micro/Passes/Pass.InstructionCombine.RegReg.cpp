#include "pch.h"
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

        // The single instruction that consumes `valueId`, ignoring phantom uses
        // that flow only into dead phis (loop-header phis for scratch temps that
        // are redefined before use). Returns invalid if the value has zero or more
        // than one real instruction use, or if its only real use is reached
        // indirectly through a phi rather than as a direct operand.
        MicroInstrRef singleDirectInstructionUse(const MicroSsaState& ssa, uint32_t valueId)
        {
            if (ssa.transitiveInstructionUseCount(valueId, 2) != 1)
                return MicroInstrRef::invalid();
            const auto* info = ssa.valueInfo(valueId);
            if (!info)
                return MicroInstrRef::invalid();
            MicroInstrRef found = MicroInstrRef::invalid();
            for (const auto& use : info->uses)
            {
                if (use.kind != MicroSsaState::UseSite::Kind::Instruction)
                    continue;
                if (found.isValid())
                    return MicroInstrRef::invalid();
                found = use.instRef;
            }
            return found;
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
        if (!ops || ops[0].reg != ops[1].reg || !ops[0].reg.isVirtualInt())
            return false;

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
}

SWC_END_NAMESPACE();
