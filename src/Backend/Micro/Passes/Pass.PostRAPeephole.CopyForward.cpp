#include "pch.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Encoder/Encoder.h"

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

namespace PostRAPeephole
{
    namespace
    {
        constexpr int K_MAX_LIVENESS_WINDOW = 32;

        bool regInList(std::span<const MicroReg> list, MicroReg reg)
        {
            for (const MicroReg r : list)
                if (r == reg)
                    return true;
            return false;
        }

        // Mirrors the "dead after consumer" scan in ConstForward: walk forward
        // from `fromRef`; the reg is dead iff the next touch is a redefinition
        // (no intervening read). Fallthrough-jumps-to-next-label are treated
        // as no-ops because a sibling pattern in this same pass erases them.
        bool regDeadAfter(Context& ctx, MicroInstrRef fromRef, MicroReg reg)
        {
            MicroInstrRef cur = ctx.nextRef(fromRef);
            for (int step = 0; step < K_MAX_LIVENESS_WINDOW && cur.isValid(); ++step, cur = ctx.nextRef(cur))
            {
                const MicroInstr* inst = ctx.instruction(cur);
                if (!inst)
                    return false;

                const MicroInstrUseDef useDef = inst->collectUseDef(*ctx.operands, nullptr);
                if (regInList(useDef.uses.span(), reg))
                    return false;
                if (regInList(useDef.defs.span(), reg))
                    return true;

                const MicroInstrOperand* ops = inst->ops(*ctx.operands);
                if (isRedundantFallthroughJumpToNextLabel(ctx, cur, *inst, ops))
                    continue;

                const MicroInstrDef& info = MicroInstr::info(inst->op);
                if (info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                    return false;
                if (info.flags.has(MicroInstrFlagsE::JumpInstruction))
                    return false;
                if (info.flags.has(MicroInstrFlagsE::IsCallInstruction))
                    return false;
            }
            return false;
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
                case MicroInstrOpcode::LoadCondRegReg:
                case MicroInstrOpcode::SetCondReg:
                    return true;
                default:
                    return false;
            }
        }
    }

    bool tryForwardCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
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

                const MicroInstrUseDef ud = inst->collectUseDef(*ctx.operands, nullptr);

                // Any read or write of `dst` before the copy means `dst`
                // carries a meaningful value there; retargeting would clobber
                // or shadow it.
                if (regInList(ud.uses.span(), dst))
                    return false;
                if (regInList(ud.defs.span(), dst))
                    return false;

                const bool defsSrc = regInList(ud.defs.span(), src);
                const bool usesSrc = regInList(ud.uses.span(), src);

                if (defsSrc)
                {
                    if (usesSrc)
                        return false; // UseDef of src: not a pure producer.
                    prevRef = cur;
                    prev    = inst;
                    break;
                }
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

        // The producer must write exactly `src` at ops[0], with no other defs
        // and no use of `dst` anywhere in its operands.
        const MicroInstrUseDef prevUseDef = prev->collectUseDef(*ctx.operands, nullptr);
        if (prevUseDef.isCall)
            return false;
        if (prevUseDef.defs.size() != 1 || prevUseDef.defs[0] != src)
            return false;
        if (prevOps[0].reg != src)
            return false;
        if (regInList(prevUseDef.uses.span(), dst))
            return false;

        if (!regDeadAfter(ctx, copyRef, src))
            return false;

        if (ctx.encoder)
        {
            // Build the retargeted instruction in a scratch buffer and ask
            // the encoder whether it is legal before committing.
            MicroInstrOperand probeOps[Action::K_MAX_OPS] = {};
            const uint8_t     numOps                     = prev->numOperands;
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

        ctx.emitRewrite(prevRef, prev->op, {newOps, numOps});
        ctx.emitErase(copyRef);
        return true;
    }
}

SWC_END_NAMESPACE();
