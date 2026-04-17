#include "pch.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"

// Post-RA variant of the pre-RA ConstProp rules. Register allocation and
// spill-code insertion regularly introduce `LoadRegImm r, imm` immediately
// followed by a single consumer (spill store, compare, arithmetic, copy) —
// material that the pre-RA combine never saw because it hadn't been emitted
// yet. Forward the immediate into the consumer and erase the now-dead
// materializing load, provided the scratch register is proven dead after
// the consumer (next touch is a redefinition, not a read).

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
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

        // True iff `reg` is guaranteed dead starting at the instruction after
        // `fromRef`: the next touch within the window is a definition, with
        // no intervening read. Labels are pure markers and safe to walk past.
        // Jumps whose target is the very next label (tryEraseTrivial's
        // "fallthrough jump" case) are about to be erased by a sibling rule
        // in the same pass; treat them as no-ops so we don't miss folds
        // whose liveness window the stale terminator would otherwise close.
        bool regDeadAfter(const Context& ctx, MicroInstrRef fromRef, MicroReg reg)
        {
            MicroInstrRef cur = ctx.nextRef(fromRef);
            for (int step = 0; step < K_MAX_LIVENESS_WINDOW && cur.isValid(); ++step, cur = ctx.nextRef(cur))
            {
                const MicroInstr* inst = ctx.instruction(cur);
                if (!inst)
                    return false;

                const MicroInstrDef& info = MicroInstr::info(inst->op);

                const MicroInstrUseDef useDef = inst->collectUseDef(*ctx.operands, nullptr);
                if (regInList(useDef.uses.span(), reg))
                    return false;
                if (regInList(useDef.defs.span(), reg))
                    return true;

                const MicroInstrOperand* ops = inst->ops(*ctx.operands);
                if (isRedundantFallthroughJumpToNextLabel(ctx, cur, *inst, ops))
                    continue;

                if (info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                    return false;
                if (info.flags.has(MicroInstrFlagsE::JumpInstruction))
                    return false;
                if (info.flags.has(MicroInstrFlagsE::IsCallInstruction))
                    return false;
            }
            return false;
        }

        struct ConsumerRewrite
        {
            MicroInstrOpcode  newOp;
            uint8_t           numOps;
            MicroInstrOperand ops[Action::K_MAX_OPS];
        };

        // If `consumer` uses `immReg` exactly once at the slot its immediate
        // form expects, build the rewritten instruction. Returns false when
        // the pattern doesn't apply or would change semantics (e.g. `immReg`
        // appearing as the consumer's base/dst in addition to its value slot).
        bool buildRewrite(ConsumerRewrite& out, const MicroInstr& consumer, const MicroInstrOperand* ops, MicroReg immReg, uint64_t imm)
        {
            if (!ops)
                return false;

            switch (consumer.op)
            {
                case MicroInstrOpcode::LoadMemReg:
                {
                    // [base, value, opBits, off] -> LoadMemImm [base, opBits, off, imm]
                    const MicroReg base = ops[0].reg;
                    if (base == immReg || ops[1].reg != immReg)
                        return false;
                    if (!base.isAnyInt())
                        return false;

                    const MicroOpBits bits = ops[2].opBits;
                    const uint64_t    off  = ops[3].valueU64;
                    out.newOp              = MicroInstrOpcode::LoadMemImm;
                    out.numOps             = 4;
                    out.ops[0].reg         = base;
                    out.ops[1].opBits      = bits;
                    out.ops[2].valueU64    = off;
                    out.ops[3].setImmediateValue(ApInt(imm & getBitsMask(bits), getNumBits(bits)));
                    return true;
                }

                case MicroInstrOpcode::CmpRegReg:
                {
                    // [a, b, opBits] -> CmpRegImm [a, opBits, imm]. Only fold when
                    // `immReg` is the RHS; swapping operands here would also
                    // require rewriting every flag consumer downstream.
                    if (ops[0].reg == immReg || ops[1].reg != immReg)
                        return false;
                    if (!ops[0].reg.isAnyInt())
                        return false;

                    const MicroOpBits bits = ops[2].opBits;
                    out.newOp              = MicroInstrOpcode::CmpRegImm;
                    out.numOps             = 3;
                    out.ops[0].reg         = ops[0].reg;
                    out.ops[1].opBits      = bits;
                    out.ops[2].setImmediateValue(ApInt(imm & getBitsMask(bits), getNumBits(bits)));
                    return true;
                }

                case MicroInstrOpcode::OpBinaryRegReg:
                {
                    // [dst, rhs, opBits, microOp] -> OpBinaryRegImm [dst, opBits, microOp, imm]
                    if (ops[0].reg == immReg || ops[1].reg != immReg)
                        return false;
                    if (!ops[0].reg.isAnyInt())
                        return false;

                    const MicroOpBits bits = ops[2].opBits;
                    out.newOp              = MicroInstrOpcode::OpBinaryRegImm;
                    out.numOps             = 4;
                    out.ops[0].reg         = ops[0].reg;
                    out.ops[1].opBits      = bits;
                    out.ops[2].microOp     = ops[3].microOp;
                    out.ops[3].setImmediateValue(ApInt(imm & getBitsMask(bits), getNumBits(bits)));
                    return true;
                }

                case MicroInstrOpcode::LoadRegReg:
                {
                    // [dst, src, opBits] -> LoadRegImm [dst, opBits, imm]
                    if (ops[0].reg == immReg || ops[1].reg != immReg)
                        return false;
                    if (!ops[0].reg.isAnyInt())
                        return false;

                    const MicroOpBits bits = ops[2].opBits;
                    out.newOp              = MicroInstrOpcode::LoadRegImm;
                    out.numOps             = 3;
                    out.ops[0].reg         = ops[0].reg;
                    out.ops[1].opBits      = bits;
                    out.ops[2].setImmediateValue(ApInt(imm & getBitsMask(bits), getNumBits(bits)));
                    return true;
                }

                default:
                    return false;
            }
        }
    }

    bool tryForwardLoadRegImm(Context& ctx, MicroInstrRef defRef, const MicroInstr& defInst)
    {
        if (defInst.op != MicroInstrOpcode::LoadRegImm)
            return false;
        if (ctx.isClaimed(defRef))
            return false;

        const MicroInstrOperand* defOps = defInst.ops(*ctx.operands);
        if (!defOps || defOps[2].hasWideImmediateValue())
            return false;

        const MicroReg immReg = defOps[0].reg;
        if (!immReg.isAnyInt())
            return false;
        const uint64_t imm = defOps[2].valueU64;

        // First instruction reaching `immReg` after the LoadRegImm is our
        // candidate consumer. Bail on any control flow in between: the
        // immediate load might be live on an alternate path.
        MicroInstrRef consumerRef = MicroInstrRef::invalid();
        {
            MicroInstrRef cur = ctx.nextRef(defRef);
            for (int step = 0; step < K_MAX_LIVENESS_WINDOW && cur.isValid(); ++step, cur = ctx.nextRef(cur))
            {
                const MicroInstr* inst = ctx.instruction(cur);
                if (!inst)
                    return false;

                const MicroInstrUseDef ud = inst->collectUseDef(*ctx.operands, nullptr);
                if (regInList(ud.uses.span(), immReg))
                {
                    consumerRef = cur;
                    break;
                }
                if (regInList(ud.defs.span(), immReg))
                    return false;

                const MicroInstrOperand* scanOps = inst->ops(*ctx.operands);
                if (isRedundantFallthroughJumpToNextLabel(ctx, cur, *inst, scanOps))
                    continue;

                const MicroInstrDef& scanInfo = MicroInstr::info(inst->op);
                if (scanInfo.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                    return false;
                if (scanInfo.flags.has(MicroInstrFlagsE::JumpInstruction))
                    return false;
                if (scanInfo.flags.has(MicroInstrFlagsE::IsCallInstruction))
                    return false;
            }
        }
        if (!consumerRef.isValid())
            return false;

        const MicroInstr* consumer = ctx.instruction(consumerRef);
        if (!consumer)
            return false;

        const MicroInstrOperand* consumerOps = ctx.operandsFor(consumerRef);

        ConsumerRewrite rewrite;
        if (!buildRewrite(rewrite, *consumer, consumerOps, immReg, imm))
            return false;

        // Pre-RA Legalize materialized this LoadRegImm + reg-form consumer
        // specifically because the immediate can't be encoded inline on this
        // target. Ask the encoder before undoing that decision.
        if (ctx.encoder)
        {
            MicroInstr probe;
            probe.op          = rewrite.newOp;
            probe.numOperands = rewrite.numOps;
            MicroConformanceIssue issue;
            if (ctx.encoder->queryConformanceIssue(issue, probe, rewrite.ops))
                return false;
        }

        if (!regDeadAfter(ctx, consumerRef, immReg))
            return false;

        if (!ctx.claimAll({defRef, consumerRef}))
            return false;

        const std::span rewrittenOps(rewrite.ops, rewrite.numOps);
        ctx.emitRewrite(consumerRef, rewrite.newOp, rewrittenOps);
        ctx.emitErase(defRef);
        return true;
    }
}

SWC_END_NAMESPACE();
