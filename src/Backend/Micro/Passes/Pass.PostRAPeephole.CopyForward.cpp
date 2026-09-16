#include "pch.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroPassHelpers.h"
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
        constexpr int      K_MAX_LIVENESS_WINDOW    = 32;
        constexpr int      K_MAX_SAME_COPY_WINDOW   = 16;
        constexpr uint32_t K_MAX_COPY_SOURCE_WINDOW = 16;

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

    // Coalesce mov D,S; op D; mov S,D without requiring D to be dead:
    // perform op S and finish with mov D,S, preserving both final values.
    bool tryFoldCopyRoundTrip(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef))
            return false;
        const auto* copy = copyInst.ops(*ctx.operands);
        if (!copy || !copy[0].reg.isInt() || !copy[1].reg.isInt() || copy[0].reg == copy[1].reg ||
            ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg) ||
            (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef opRef = ctx.nextRef(copyRef);
        const MicroInstr*   op    = ctx.instruction(opRef);
        if (!op || (op->op != MicroInstrOpcode::OpBinaryRegImm && op->op != MicroInstrOpcode::OpUnaryReg))
            return false;
        const auto* ops = op->ops(*ctx.operands);
        if (!ops || ops[0].reg != copy[0].reg || ops[1].opBits != copy[2].opBits)
            return false;
        switch (ops[2].microOp)
        {
            case MicroOp::ShiftLeft:
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticLeft:
            case MicroOp::ShiftArithmeticRight:
            case MicroOp::RotateLeft:
            case MicroOp::RotateRight:
                if (op->op != MicroInstrOpcode::OpBinaryRegImm || ops[3].hasWideImmediateValue() ||
                    (ops[3].valueU64 & (getNumBits(ops[1].opBits) - 1)) == 0)
                    return false;
                break;
            case MicroOp::Negate:
            case MicroOp::BitwiseNot:
                if (op->op != MicroInstrOpcode::OpUnaryReg)
                    return false;
                break;
            default:
                return false;
        }
        const MicroInstrRef backRef = ctx.nextRef(opRef);
        const MicroInstr*   back    = ctx.instruction(backRef);
        if (!back || back->op != MicroInstrOpcode::LoadRegReg)
            return false;
        const auto* backOps = back->ops(*ctx.operands);
        if (!backOps || backOps[0].reg != copy[1].reg || backOps[1].reg != copy[0].reg || backOps[2].opBits != copy[2].opBits)
            return false;
        MicroInstrOperand rewritten[4] = {};
        for (uint8_t i = 0; i < op->numOperands; ++i)
            rewritten[i] = ops[i];
        rewritten[0].reg = copy[1].reg;
        MicroConformanceIssue issue;
        if ((ctx.encoder && ctx.encoder->queryConformanceIssue(issue, *op, rewritten)) || !ctx.claimAll({copyRef, opRef, backRef}))
            return false;
        ctx.emitErase(copyRef);
        ctx.emitRewrite(opRef, op->op, std::span{rewritten, op->numOperands});
        ctx.emitRewrite(backRef, copyInst.op, std::span{copy, copyInst.numOperands});
        return true;
    }

    // Keep value additions intact through SSA/loop optimization, then merge
    // the physical input copy with a flag-dead add. A 32-bit LEA needs only
    // the low input bits even though its addressing operands are 64-bit.
    bool tryFoldCopyIntoIntegerAdd(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef))
            return false;
        const auto* copy = copyInst.ops(*ctx.operands);
        if (!copy || !copy[0].reg.isInt() || !copy[1].reg.isInt() || copy[0].reg == copy[1].reg ||
            ctx.isPrivateFrameBase(copy[0].reg) || (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef addRef = ctx.nextRef(copyRef);
        const MicroInstr*   add    = ctx.instruction(addRef);
        if (!add || add->op != MicroInstrOpcode::OpBinaryRegReg || ctx.isClaimed(addRef))
            return false;
        const auto* ops = add->ops(*ctx.operands);
        if (!ops || ops[3].microOp != MicroOp::Add || ops[0].reg != copy[0].reg || !ops[1].reg.isInt() ||
            (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64) ||
            getNumBits(copy[2].opBits) < getNumBits(ops[2].opBits) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, addRef, ctx.builder))
            return false;
        MicroInstrOperand address[8] = {};
        address[0].reg               = copy[0].reg;
        address[1].reg               = copy[1].reg;
        address[2].reg               = ops[1].reg == copy[0].reg ? copy[1].reg : ops[1].reg;
        address[3].opBits            = ops[2].opBits;
        address[4].opBits            = MicroOpBits::B64;
        address[5].valueU64          = 1;
        MicroInstr probe;
        probe.op          = MicroInstrOpcode::LoadAddrAmcRegMem;
        probe.numOperands = 8;
        MicroConformanceIssue issue;
        if ((ctx.encoder && ctx.encoder->queryConformanceIssue(issue, probe, address)) || !ctx.claimAll({copyRef, addRef}))
            return false;
        ctx.emitRewrite(addRef, probe.op, address, true);
        // Other readers, including implicit ABI uses, remain the DCE's job.
        return true;
    }

    // A later operation can read the original register directly. Leave the
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

        // Only the equality established by the copy is propagated. Stop when
        // either register changes or control leaves the straight line. Claim
        // every instruction crossed so later queued rewrites preserve that proof.
        SmallVector<MicroInstrRef, K_MAX_COPY_SOURCE_WINDOW + 1> observed;
        observed.push_back(copyRef);
        MicroInstrRef nextRef = ctx.nextRef(copyRef);
        for (uint32_t step = 0; step < K_MAX_COPY_SOURCE_WINDOW && nextRef.isValid(); ++step, nextRef = ctx.nextRef(nextRef))
        {
            const MicroInstr* next = ctx.instruction(nextRef);
            if (!next || ctx.isClaimed(nextRef))
                return false;
            const auto& info = MicroInstr::info(next->op);
            if (next->op == MicroInstrOpcode::Label || info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction) || info.flags.has(MicroInstrFlagsE::JumpInstruction))
                return false;
            observed.push_back(nextRef);
            const bool extends        = next->op == MicroInstrOpcode::LoadZeroExtRegReg || next->op == MicroInstrOpcode::LoadSignedExtRegReg;
            const bool conditional    = next->op == MicroInstrOpcode::LoadCondRegReg;
            const bool compareRegs    = next->op == MicroInstrOpcode::CmpRegReg;
            const bool compareImm     = next->op == MicroInstrOpcode::CmpRegImm;
            const bool indexedAddress = next->op == MicroInstrOpcode::LoadAddrAmcRegMem;
            const bool address        = indexedAddress || next->op == MicroInstrOpcode::LoadAddrRegMem;
            if (extends || conditional || compareRegs || compareImm || address || next->op == MicroInstrOpcode::OpBinaryRegReg)
            {
                const MicroInstrOperand* ops = next->ops(*ctx.operands);
                if (!ops)
                    return false;
                const uint32_t widthOperand = extends || conditional ? 3 : compareImm ? 1
                                                                                      : 2;
                // Address inputs use the full pointer width even when the
                // address result is requested in a narrower destination.
                const MicroOpBits readBits = address ? MicroOpBits::B64 : ops[widthOperand].opBits;
                if (ops[0].reg.isInt() && getNumBits(readBits) <= getNumBits(copyOps[2].opBits))
                {
                    MicroInstrOperand rewritten[Action::K_MAX_OPS];
                    std::ranges::copy(std::span{ops, next->numOperands}, rewritten);
                    bool           changed      = false;
                    const uint32_t firstOperand = compareRegs || compareImm ? 0 : 1;
                    const uint32_t lastOperand  = indexedAddress ? 2 : compareImm ? 0
                                                                                  : 1;
                    for (uint32_t i = firstOperand; i <= lastOperand; ++i)
                    {
                        if (rewritten[i].reg == copyOps[0].reg)
                        {
                            rewritten[i].reg = copyOps[1].reg;
                            changed          = true;
                        }
                    }
                    MicroConformanceIssue issue;
                    if (changed && (!ctx.encoder || !ctx.encoder->queryConformanceIssue(issue, *next, rewritten)))
                    {
                        if (!ctx.claimAll(observed.span()))
                            return false;
                        ctx.emitRewrite(nextRef, next->op, std::span{rewritten, next->numOperands});
                        return true;
                    }
                }
            }
            const MicroInstrUseDef ud = next->collectUseDef(*ctx.operands, ctx.encoder);
            if (regInList(ud.defs, copyOps[0].reg) || regInList(ud.defs, copyOps[1].reg))
                return false;
        }
        return false;
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
