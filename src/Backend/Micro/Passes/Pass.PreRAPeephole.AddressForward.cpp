#include "pch.h"
#include "Backend/Micro/Passes/Pass.PreRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PreRaPeephole
{
    namespace
    {
        bool isEncodableAmcScale(const uint64_t scale)
        {
            return scale == 1 || scale == 2 || scale == 4 || scale == 8;
        }

        constexpr uint32_t K_MAX_ADDR_FORWARD_COPIES = 8;

        // The first reader of the address on the straight line after its
        // definition - the candidate consumer for the lea. Folding the lea into
        // that consumer (rewriting it to base+index, leaving the lea for any
        // other uses) is sound as long as base/index hold the same value there.
        // Lowering materializes every operand address before the loads
        // (`lea a; lea b; load [a]; load [b]`), so the walk crosses copies and
        // any other instruction that neither reads the address nor writes
        // addrReg/base/index; it bails at a label, a jump, a call or a return,
        // at an instruction another rule already claimed, and after the budget.
        // The crossed instructions are returned so the caller can claim them:
        // a rule rewriting one of them in the same sweep (retargeting a
        // producer onto an input, say) would break the equality this relies on.
        MicroInstrRef skipCopiesToConsumer(const Context& ctx, MicroInstrRef defRef, MicroReg addrReg, MicroReg inputA, MicroReg inputB, SmallVector<MicroInstrRef, K_MAX_ADDR_FORWARD_COPIES>& outCrossed)
        {
            outCrossed.clear();
            MicroInstrRef cur = ctx.nextRef(defRef);
            for (uint32_t step = 0; step < K_MAX_ADDR_FORWARD_COPIES && cur.isValid(); ++step)
            {
                const MicroInstr* w = ctx.instruction(cur);
                if (!w || ctx.isClaimed(cur))
                    return MicroInstrRef::invalid();

                const MicroInstrDef& info = MicroInstr::info(w->op);
                if (w->op == MicroInstrOpcode::Label || info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                    info.flags.has(MicroInstrFlagsE::JumpInstruction) || info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                    return MicroInstrRef::invalid();

                const MicroInstrUseDef useDef = w->collectUseDef(*ctx.operands, ctx.encoder);
                if (w->op != MicroInstrOpcode::LoadRegReg && std::ranges::find(useDef.uses, addrReg) != useDef.uses.end())
                    return cur; // candidate consumer.

                for (const MicroReg def : useDef.defs)
                {
                    if (def == addrReg || def == inputA || (inputB.isValid() && def == inputB))
                        return MicroInstrRef::invalid(); // an addressing input changed.
                }

                outCrossed.push_back(cur);
                cur = ctx.nextRef(cur);
            }
            return MicroInstrRef::invalid();
        }

        bool claimConsumerAndCrossed(Context& ctx, MicroInstrRef consumerRef, std::span<const MicroInstrRef> crossed)
        {
            if (!ctx.claimAll({consumerRef}))
                return false;
            for (const MicroInstrRef ref : crossed)
                ctx.claimed.insert(ref.get());
            return true;
        }

        struct ConsumerRewrite
        {
            MicroInstrOpcode  newOp                  = MicroInstrOpcode::Nop;
            uint8_t           numOps                 = 0;
            MicroInstrOperand ops[Action::K_MAX_OPS] = {};
            bool              allocOps               = false;
        };

        void copyOperands(ConsumerRewrite& out, const MicroInstr& consumer, const MicroInstrOperand* ops)
        {
            out.newOp  = consumer.op;
            out.numOps = consumer.numOperands;
            for (uint8_t idx = 0; idx < consumer.numOperands; ++idx)
                out.ops[idx] = ops[idx];
        }

        bool buildAddrRewrite(ConsumerRewrite& out, const MicroInstr& consumer, const MicroInstrOperand* ops, MicroReg addrReg, MicroReg baseReg, uint64_t addrOff)
        {
            if (!ops)
                return false;

            if (addrOff == 0)
            {
                Action substitute;
                if (buildUseOnlyRegRewrite(substitute, consumer, ops, addrReg, baseReg))
                {
                    out.newOp  = substitute.newOp;
                    out.numOps = substitute.numOps;
                    for (uint8_t idx = 0; idx < substitute.numOps; ++idx)
                        out.ops[idx] = substitute.ops[idx];
                    return true;
                }
            }

            switch (consumer.op)
            {
                case MicroInstrOpcode::LoadRegReg:
                    if (ops[1].reg == addrReg)
                    {
                        out.newOp           = MicroInstrOpcode::LoadAddrRegMem;
                        out.numOps          = 4;
                        out.allocOps        = true;
                        out.ops[0].reg      = ops[0].reg;
                        out.ops[1].reg      = baseReg;
                        out.ops[2].opBits   = ops[2].opBits;
                        out.ops[3].valueU64 = addrOff;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadRegMem:
                case MicroInstrOpcode::LoadVecRegMem:
                case MicroInstrOpcode::VecUnaryRegMem:
                    if (ops[1].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[1].reg      = baseReg;
                        out.ops[3].valueU64 = ops[3].valueU64 + addrOff;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::StoreVecMemReg:
                    if (ops[0].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[0].reg      = baseReg;
                        out.ops[3].valueU64 = ops[3].valueU64 + addrOff;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadSignedExtRegMem:
                case MicroInstrOpcode::LoadZeroExtRegMem:
                    if (ops[1].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[1].reg      = baseReg;
                        out.ops[4].valueU64 = ops[4].valueU64 + addrOff;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadMemReg:
                    if (ops[0].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[0].reg      = baseReg;
                        out.ops[3].valueU64 = ops[3].valueU64 + addrOff;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadMemImm:
                    if (ops[0].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[0].reg      = baseReg;
                        out.ops[2].valueU64 = ops[2].valueU64 + addrOff;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::CmpMemReg:
                    if (ops[0].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[0].reg      = baseReg;
                        out.ops[3].valueU64 = ops[3].valueU64 + addrOff;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::CmpMemImm:
                    if (ops[0].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[0].reg      = baseReg;
                        out.ops[2].valueU64 = ops[2].valueU64 + addrOff;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::OpUnaryMem:
                    if (ops[0].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[0].reg      = baseReg;
                        out.ops[3].valueU64 = ops[3].valueU64 + addrOff;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::OpBinaryRegMem:
                    if (ops[1].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[1].reg      = baseReg;
                        out.ops[4].valueU64 = ops[4].valueU64 + addrOff;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::OpBinaryMemReg:
                    if (ops[0].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[0].reg      = baseReg;
                        out.ops[4].valueU64 = ops[4].valueU64 + addrOff;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::OpBinaryMemImm:
                    if (ops[0].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[0].reg      = baseReg;
                        out.ops[3].valueU64 = ops[3].valueU64 + addrOff;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadAddrRegMem:
                    if (ops[1].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[1].reg      = baseReg;
                        out.ops[3].valueU64 = ops[3].valueU64 + addrOff;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadAmcRegMem:
                    if (ops[1].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[1].reg      = baseReg;
                        out.ops[6].valueU64 = ops[6].valueU64 + addrOff;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadAmcMemReg:
                    if (ops[0].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[0].reg      = baseReg;
                        out.ops[6].valueU64 = ops[6].valueU64 + addrOff;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadAmcMemImm:
                    if (ops[0].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[0].reg      = baseReg;
                        out.ops[6].valueU64 = ops[6].valueU64 + addrOff;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadAddrAmcRegMem:
                    if (ops[1].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[1].reg      = baseReg;
                        out.ops[6].valueU64 = ops[6].valueU64 + addrOff;
                        return true;
                    }
                    return false;

                default:
                    return false;
            }
        }

        bool buildAddrAmcRewrite(ConsumerRewrite& out, const Context& ctx, const MicroInstr& consumer, const MicroInstrOperand* ops, MicroReg addrReg, MicroReg baseReg, MicroReg indexReg, MicroOpBits addrBits, uint64_t scale, uint64_t add)
        {
            if (!ops)
                return false;
            if (hasVirtualForbiddenPhysRegs(ctx, addrReg) || hasVirtualForbiddenPhysRegs(ctx, baseReg) || hasVirtualForbiddenPhysRegs(ctx, indexReg))
                return false;

            switch (consumer.op)
            {
                case MicroInstrOpcode::LoadRegReg:
                    if (ops[1].reg == addrReg)
                    {
                        out.newOp           = MicroInstrOpcode::LoadAddrAmcRegMem;
                        out.numOps          = 8;
                        out.allocOps        = true;
                        out.ops[0].reg      = ops[0].reg;
                        out.ops[1].reg      = baseReg;
                        out.ops[2].reg      = indexReg;
                        out.ops[3].opBits   = ops[2].opBits;
                        out.ops[4].opBits   = addrBits;
                        out.ops[5].valueU64 = scale;
                        out.ops[6].valueU64 = add;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadRegMem:
                    if (ops[1].reg == addrReg)
                    {
                        if (!isEncodableAmcScale(scale))
                            return false;
                        out.newOp           = MicroInstrOpcode::LoadAmcRegMem;
                        out.numOps          = 8;
                        out.allocOps        = true;
                        out.ops[0].reg      = ops[0].reg;
                        out.ops[1].reg      = baseReg;
                        out.ops[2].reg      = indexReg;
                        out.ops[3].opBits   = ops[2].opBits;
                        out.ops[4].opBits   = addrBits;
                        out.ops[5].valueU64 = scale;
                        out.ops[6].valueU64 = add + ops[3].valueU64;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadVecRegMem:
                    // The vector load takes the same indexed form as the
                    // scalar one; the encoder writes the 128-bit move.
                    if (ops[1].reg == addrReg)
                    {
                        if (!isEncodableAmcScale(scale))
                            return false;
                        out.newOp           = MicroInstrOpcode::LoadAmcRegMem;
                        out.numOps          = 8;
                        out.allocOps        = true;
                        out.ops[0].reg      = ops[0].reg;
                        out.ops[1].reg      = baseReg;
                        out.ops[2].reg      = indexReg;
                        out.ops[3].opBits   = ops[2].opBits;
                        out.ops[4].opBits   = addrBits;
                        out.ops[5].valueU64 = scale;
                        out.ops[6].valueU64 = add + ops[3].valueU64;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::VecUnaryRegMem:
                    // The memory widening has its indexed form too.
                    if (ops[1].reg == addrReg)
                    {
                        if (!isEncodableAmcScale(scale))
                            return false;
                        out.newOp           = MicroInstrOpcode::VecUnaryAmcRegMem;
                        out.numOps          = 8;
                        out.allocOps        = true;
                        out.ops[0].reg      = ops[0].reg;
                        out.ops[1].reg      = baseReg;
                        out.ops[2].reg      = indexReg;
                        out.ops[3].opBits   = ops[2].opBits;
                        out.ops[4].opBits   = addrBits;
                        out.ops[5].valueU64 = scale;
                        out.ops[6].valueU64 = add + ops[3].valueU64;
                        out.ops[7].microOp  = ops[4].microOp;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::StoreVecMemReg:
                    if (ops[0].reg == addrReg)
                    {
                        if (!isEncodableAmcScale(scale))
                            return false;
                        out.newOp           = MicroInstrOpcode::LoadAmcMemReg;
                        out.numOps          = 8;
                        out.allocOps        = true;
                        out.ops[0].reg      = baseReg;
                        out.ops[1].reg      = indexReg;
                        out.ops[2].reg      = ops[1].reg;
                        out.ops[3].opBits   = addrBits;
                        out.ops[4].opBits   = ops[2].opBits;
                        out.ops[5].valueU64 = scale;
                        out.ops[6].valueU64 = add + ops[3].valueU64;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadMemReg:
                    if (ops[0].reg == addrReg)
                    {
                        if (!isEncodableAmcScale(scale))
                            return false;
                        out.newOp           = MicroInstrOpcode::LoadAmcMemReg;
                        out.numOps          = 8;
                        out.allocOps        = true;
                        out.ops[0].reg      = baseReg;
                        out.ops[1].reg      = indexReg;
                        out.ops[2].reg      = ops[1].reg;
                        out.ops[3].opBits   = addrBits;
                        out.ops[4].opBits   = ops[2].opBits;
                        out.ops[5].valueU64 = scale;
                        out.ops[6].valueU64 = add + ops[3].valueU64;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadMemImm:
                    if (ops[0].reg == addrReg)
                    {
                        if (!isEncodableAmcScale(scale))
                            return false;
                        out.newOp           = MicroInstrOpcode::LoadAmcMemImm;
                        out.numOps          = 8;
                        out.allocOps        = true;
                        out.ops[0].reg      = baseReg;
                        out.ops[1].reg      = indexReg;
                        out.ops[3].opBits   = addrBits;
                        out.ops[4].opBits   = ops[1].opBits;
                        out.ops[5].valueU64 = scale;
                        out.ops[6].valueU64 = add + ops[2].valueU64;
                        out.ops[7]          = ops[3];
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadAddrRegMem:
                    if (ops[1].reg == addrReg)
                    {
                        out.newOp           = MicroInstrOpcode::LoadAddrAmcRegMem;
                        out.numOps          = 8;
                        out.allocOps        = true;
                        out.ops[0].reg      = ops[0].reg;
                        out.ops[1].reg      = baseReg;
                        out.ops[2].reg      = indexReg;
                        out.ops[3].opBits   = ops[2].opBits;
                        out.ops[4].opBits   = addrBits;
                        out.ops[5].valueU64 = scale;
                        out.ops[6].valueU64 = add + ops[3].valueU64;
                        return true;
                    }
                    return false;

                default:
                    return false;
            }
        }
    }

    bool tryForwardLoadAddr(Context& ctx, const MicroInstrRef defRef, const MicroInstr& defInst)
    {
        if (defInst.op != MicroInstrOpcode::LoadAddrRegMem || ctx.isClaimed(defRef))
            return false;

        const MicroInstrOperand* defOps = defInst.ops(*ctx.operands);
        if (!defOps)
            return false;

        const MicroReg addrReg = defOps[0].reg;
        const MicroReg baseReg = defOps[1].reg;
        if (!addrReg.isVirtualInt() || !baseReg.isAnyInt())
            return false;
        if (hasVirtualForbiddenPhysRegs(ctx, addrReg) || hasVirtualForbiddenPhysRegs(ctx, baseReg))
            return false;

        // `lea r, [r + C]` steps a pointer in place. Its base is the value
        // before the step, which no consumer can read any more: forwarding it
        // would add the step to an address that already holds it, once per
        // sweep, and the loop would never settle.
        if (addrReg == baseReg)
            return false;

        SmallVector<MicroInstrRef, K_MAX_ADDR_FORWARD_COPIES> crossed;
        const MicroInstrRef                                   consumerRef = skipCopiesToConsumer(ctx, defRef, addrReg, baseReg, MicroReg::invalid(), crossed);
        if (!consumerRef.isValid() || ctx.isClaimed(consumerRef))
            return false;

        const MicroInstr* consumer = ctx.instruction(consumerRef);
        if (!consumer)
            return false;

        ConsumerRewrite rewrite;
        if (!buildAddrRewrite(rewrite, *consumer, ctx.operandsFor(consumerRef), addrReg, baseReg, defOps[3].valueU64))
            return false;

        if (!claimConsumerAndCrossed(ctx, consumerRef, crossed))
            return false;

        const std::span rewrittenOps(rewrite.ops, rewrite.numOps);
        ctx.emitRewrite(consumerRef, rewrite.newOp, rewrittenOps, rewrite.allocOps);
        return true;
    }

    // `lea r, [s]` is `mov r, s`, which the copy passes then fold away; the
    // lea form stays opaque to them.
    bool tryFoldZeroDisplacementLoadAddr(Context& ctx, const MicroInstrRef defRef, const MicroInstr& defInst)
    {
        if (defInst.op != MicroInstrOpcode::LoadAddrRegMem || ctx.isClaimed(defRef))
            return false;

        const MicroInstrOperand* defOps = defInst.ops(*ctx.operands);
        if (!defOps || defOps[3].valueU64 != 0 || defOps[2].opBits != MicroOpBits::B64)
            return false;
        if (!defOps[0].reg.isVirtualInt() || !defOps[1].reg.isVirtualInt() || defOps[0].reg == defOps[1].reg)
            return false;
        if (!ctx.claimAll({defRef}))
            return false;

        MicroInstrOperand ops[3];
        ops[0].reg    = defOps[0].reg;
        ops[1].reg    = defOps[1].reg;
        ops[2].opBits = MicroOpBits::B64;
        ctx.emitRewrite(defRef, MicroInstrOpcode::LoadRegReg, std::span<const MicroInstrOperand>(ops, 3), true);
        return true;
    }

    bool tryForwardLoadAddrAmc(Context& ctx, const MicroInstrRef defRef, const MicroInstr& defInst)
    {
        if (defInst.op != MicroInstrOpcode::LoadAddrAmcRegMem || ctx.isClaimed(defRef))
            return false;

        const MicroInstrOperand* defOps = defInst.ops(*ctx.operands);
        if (!defOps)
            return false;

        const MicroReg addrReg = defOps[0].reg;
        if (!addrReg.isVirtualInt())
            return false;
        if (hasVirtualForbiddenPhysRegs(ctx, addrReg) || hasVirtualForbiddenPhysRegs(ctx, defOps[1].reg) || hasVirtualForbiddenPhysRegs(ctx, defOps[2].reg))
            return false;
        if (addrReg == defOps[1].reg || addrReg == defOps[2].reg)
            return false;

        SmallVector<MicroInstrRef, K_MAX_ADDR_FORWARD_COPIES> crossed;
        const MicroInstrRef                                   consumerRef = skipCopiesToConsumer(ctx, defRef, addrReg, defOps[1].reg, defOps[2].reg, crossed);
        if (!consumerRef.isValid() || ctx.isClaimed(consumerRef))
            return false;

        const MicroInstr* consumer = ctx.instruction(consumerRef);
        if (!consumer)
            return false;

        ConsumerRewrite rewrite;
        if (!buildAddrAmcRewrite(rewrite, ctx, *consumer, ctx.operandsFor(consumerRef), addrReg, defOps[1].reg, defOps[2].reg, defOps[4].opBits, defOps[5].valueU64, defOps[6].valueU64))
            return false;

        if (!claimConsumerAndCrossed(ctx, consumerRef, crossed))
            return false;

        const std::span rewrittenOps(rewrite.ops, rewrite.numOps);
        ctx.emitRewrite(consumerRef, rewrite.newOp, rewrittenOps, rewrite.allocOps);
        return true;
    }
}

SWC_END_NAMESPACE();
