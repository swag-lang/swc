#include "pch.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"

// Post-RA copy coalescing: when a value is produced into a scratch register
// only to be immediately moved to another physical register, retarget the
// producer directly at the final destination and erase the move.
//
//     LoadRegMem  rA, [mem]        ->   LoadRegMem  rB, [mem]
//     LoadRegReg  rB, rA, bits          (move erased)
//
// Common shape is ABI marshalling after a spill reload:
//     load_reg_mem rax, [rsp+X]
//     load_reg_reg rcx, rax              -- rcx is the ABI arg slot
//     call                               -- clobbers rax anyway
//
// We only touch producers whose single def is ops[0] with Def mode (no
// UseDef), so retargeting is a straight operand swap. The encoder is
// queried before committing - some instructions pin specific physical regs
// (e.g. shifts on %cl) and those must not be rewritten.

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
{
    namespace
    {
        constexpr int K_MAX_LIVENESS_WINDOW = 32;
        constexpr int K_MAX_SAME_COPY_WINDOW = 16;

        bool regInList(std::span<const MicroReg> list, MicroReg reg)
        {
            for (const MicroReg r : list)
                if (r == reg)
                    return true;
            return false;
        }

        bool regDeadAfter(const Context& ctx, MicroInstrRef fromRef, MicroReg reg)
        {
            return regIsDeadAfter(ctx, fromRef, reg);
        }

        // Producers whose only register write is a pure Def at ops[0]. Anything
        // that consumes its own destination (UseDef) or has fixed-register
        // semantics beyond what regModes expresses is excluded.
        bool isSimpleSingleDefProducer(MicroInstrOpcode op)
        {
            switch (op)
            {
                case MicroInstrOpcode::LoadRegImm:
                case MicroInstrOpcode::LoadRegMem:
                case MicroInstrOpcode::LoadRegReg:
                case MicroInstrOpcode::LoadRegPtrImm:
                case MicroInstrOpcode::LoadRegPtrReloc:
                case MicroInstrOpcode::LoadSignedExtRegMem:
                case MicroInstrOpcode::LoadZeroExtRegMem:
                case MicroInstrOpcode::LoadSignedExtRegReg:
                case MicroInstrOpcode::LoadZeroExtRegReg:
                case MicroInstrOpcode::LoadAddrRegMem:
                case MicroInstrOpcode::SetCondReg:
                    return true;
                default:
                    return false;
            }
        }
    }

    // A copy whose destination already holds exactly what it is about to be
    // given again. The shape comes from the lowering of an operand a form
    // requires in a named register: two shifts by the same count each move
    // that count into rcx, and the second move has nothing to do. Same
    // registers, same width - a narrower copy left the upper half of the
    // destination with something else - and nothing in between writes either
    // register or leaves the straight line.
    bool tryEraseRedundantCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (copyInst.op != MicroInstrOpcode::LoadRegReg || ctx.isClaimed(copyRef))
            return false;

        const MicroInstrOperand* copyOps = copyInst.ops(*ctx.operands);
        if (!copyOps)
            return false;

        const MicroReg    dst    = copyOps[0].reg;
        const MicroReg    src    = copyOps[1].reg;
        const MicroOpBits opBits = copyOps[2].opBits;
        if (dst == src || !dst.isInt() || !src.isInt())
            return false;

        MicroInstrRef cur = ctx.previousRef(copyRef);
        for (int step = 0; step < K_MAX_SAME_COPY_WINDOW && cur.isValid(); ++step, cur = ctx.previousRef(cur))
        {
            const MicroInstr* inst = ctx.instruction(cur);
            if (!inst || ctx.isClaimed(cur))
                return false;

            const MicroInstrDef& info = MicroInstr::info(inst->op);
            if (info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                inst->op == MicroInstrOpcode::Label)
                return false;

            const MicroInstrOperand* ops = inst->ops(*ctx.operands);
            if (inst->op == MicroInstrOpcode::LoadRegReg && ops &&
                ops[0].reg == dst && ops[1].reg == src && ops[2].opBits == opBits)
            {
                if (!ctx.claimAll({copyRef}))
                    return false;
                ctx.emitErase(copyRef);
                return true;
            }

            const MicroInstrUseDef ud = inst->collectUseDef(*ctx.operands, ctx.encoder);
            if (regInList(ud.defs, dst) || regInList(ud.defs, src))
                return false;
        }

        return false;
    }

    // The next operation can read the original register directly. Leave the
    // copy in place: its other readers and ABI obligations belong to post-RA
    // dead-code elimination, which removes it only when they are all gone.
    bool tryForwardCopySource(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef))
            return false;
        const MicroInstrOperand* copyOps = copyInst.ops(*ctx.operands);
        if (!copyOps || !copyOps[0].reg.isInt() || !copyOps[1].reg.isInt() || copyOps[0].reg == copyOps[1].reg)
            return false;
        if (copyOps[2].opBits != MicroOpBits::B32 && copyOps[2].opBits != MicroOpBits::B64)
            return false;

        const MicroInstrRef nextRef = ctx.nextRef(copyRef);
        const MicroInstr*   next    = ctx.instruction(nextRef);
        if (!next || ctx.isClaimed(nextRef))
            return false;
        const bool extends = next->op == MicroInstrOpcode::LoadZeroExtRegReg || next->op == MicroInstrOpcode::LoadSignedExtRegReg;
        const bool compareRegs = next->op == MicroInstrOpcode::CmpRegReg;
        const bool compareImm  = next->op == MicroInstrOpcode::CmpRegImm;
        if (!extends && !compareRegs && !compareImm && next->op != MicroInstrOpcode::OpBinaryRegReg)
            return false;
        const MicroInstrOperand* ops = next->ops(*ctx.operands);
        if (!ops || !ops[0].reg.isInt())
            return false;
        const MicroOpBits readBits = ops[extends ? 3 : compareImm ? 1 : 2].opBits;
        if (getNumBits(readBits) > getNumBits(copyOps[2].opBits))
            return false;

        MicroInstrOperand rewritten[4];
        std::ranges::copy(std::span{ops, next->numOperands}, rewritten);
        bool changed = false;
        for (uint32_t i = compareRegs || compareImm ? 0 : 1; i <= (compareImm ? 0u : 1u); ++i)
        {
            if (rewritten[i].reg == copyOps[0].reg)
            {
                rewritten[i].reg = copyOps[1].reg;
                changed = true;
            }
        }
        if (!changed)
            return false;
        if (ctx.encoder)
        {
            MicroConformanceIssue issue;
            if (ctx.encoder->queryConformanceIssue(issue, *next, rewritten))
                return false;
        }
        if (!ctx.claimAll({copyRef, nextRef}))
            return false;
        ctx.emitRewrite(nextRef, next->op, std::span{rewritten, next->numOperands});
        return true;
    }

    bool tryForwardCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        // Liveness here is a linear forward scan, sound only on the pristine
        // post-RA IR. Restrict to the first sweep of the optimization loop.
        if (!ctx.allowForwarding)
            return false;
        if (copyInst.op != MicroInstrOpcode::LoadRegReg)
            return false;
        if (ctx.isClaimed(copyRef))
            return false;

        const MicroInstrOperand* copyOps = copyInst.ops(*ctx.operands);
        if (!copyOps)
            return false;

        const MicroReg dst = copyOps[0].reg;
        const MicroReg src = copyOps[1].reg;
        if (dst == src || !dst.isAnyInt() || !src.isAnyInt())
            return false;

        // Walk backward looking for the producer of `src`. We can skip
        // instructions that touch neither `src` nor `dst`, but must bail if
        // `src` is read in between (the producer's value is still observed),
        // if `dst` is read or written in between (we're about to pull the
        // producer's write forward onto `dst`), or if we cross a control-
        // flow boundary (the copy may be reachable via other paths where the
        // producer never ran).
        MicroInstrRef     prevRef = MicroInstrRef::invalid();
        const MicroInstr* prev    = nullptr;
        {
            MicroInstrRef cur = ctx.previousRef(copyRef);
            for (int step = 0; step < K_MAX_LIVENESS_WINDOW && cur.isValid(); ++step, cur = ctx.previousRef(cur))
            {
                const MicroInstr* inst = ctx.instruction(cur);
                if (!inst)
                    return false;
                if (ctx.isClaimed(cur))
                    return false;

                const MicroInstrUseDef ud = inst->collectUseDef(*ctx.operands, ctx.encoder);

                const bool defsSrc = regInList(ud.defs.span(), src);
                const bool usesSrc = regInList(ud.uses.span(), src);

                // The producer is allowed to read `dst`: its operands are read
                // before its destination is written, so retargeting it at `dst`
                // computes the same value. That is the `x = x + 1` shape every
                // scan loop ends with — `lea t, [x + 1]` then `mov x, t` — and
                // refusing it left one instruction per iteration in the hottest
                // loops of the benchmark. Every OTHER read or write of `dst`
                // before the copy still blocks: `dst` carries a live value
                // there, and retargeting would clobber or shadow it.
                if (defsSrc && !usesSrc)
                {
                    prevRef = cur;
                    prev    = inst;
                    break;
                }

                if (regInList(ud.uses.span(), dst))
                    return false;
                if (regInList(ud.defs.span(), dst))
                    return false;

                if (defsSrc)
                    return false; // UseDef of src: not a pure producer.
                if (usesSrc)
                    return false; // Intermediate read of src's future value.

                const MicroInstrDef& info = MicroInstr::info(inst->op);
                if (inst->op == MicroInstrOpcode::Label)
                    return false;
                if (info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                    return false;
                if (info.flags.has(MicroInstrFlagsE::JumpInstruction))
                    return false;
                if (info.flags.has(MicroInstrFlagsE::IsCallInstruction))
                    return false;
            }
        }

        if (!prev || !prevRef.isValid() || ctx.isClaimed(prevRef))
            return false;
        if (!isSimpleSingleDefProducer(prev->op))
            return false;

        const MicroInstrOperand* prevOps = prev->ops(*ctx.operands);
        if (!prevOps)
            return false;

        // The producer must write exactly `src` at ops[0], with no other defs.
        // It may read `dst` (see the walk above); the encoder is asked below
        // whether the retargeted form, where source and destination coincide,
        // is encodable at all.
        const MicroInstrUseDef prevUseDef = prev->collectUseDef(*ctx.operands, ctx.encoder);
        if (prevUseDef.isCall)
            return false;
        if (prevUseDef.defs.size() != 1 || prevUseDef.defs[0] != src)
            return false;
        if (prevOps[0].reg != src)
            return false;

        if (!regDeadAfter(ctx, copyRef, src))
            return false;

        if (ctx.encoder)
        {
            // Build the retargeted instruction in a scratch buffer and ask
            // the encoder whether it is legal before committing.
            MicroInstrOperand probeOps[Action::K_MAX_OPS] = {};
            const uint8_t     numOps                      = prev->numOperands;
            if (numOps > Action::K_MAX_OPS)
                return false;
            for (uint8_t i = 0; i < numOps; ++i)
                probeOps[i] = prevOps[i];
            probeOps[0].reg = dst;

            MicroInstr probe;
            probe.op          = prev->op;
            probe.numOperands = numOps;

            MicroConformanceIssue issue;
            if (ctx.encoder->queryConformanceIssue(issue, probe, probeOps))
                return false;
        }

        if (!ctx.claimAll({prevRef, copyRef}))
            return false;

        MicroInstrOperand newOps[Action::K_MAX_OPS] = {};
        const uint8_t     numOps                    = prev->numOperands;
        for (uint8_t i = 0; i < numOps; ++i)
            newOps[i] = prevOps[i];
        newOps[0].reg = dst;

        const std::span rewrittenOps(newOps, numOps);
        ctx.emitRewrite(prevRef, prev->op, rewrittenOps);
        ctx.emitErase(copyRef);
        return true;
    }
}

SWC_END_NAMESPACE();
