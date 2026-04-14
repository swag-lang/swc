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

        bool buildAddrRewrite(ConsumerRewrite& out,
                              const MicroInstr& consumer,
                              const MicroInstrOperand* ops,
                              const MicroReg addrReg,
                              const MicroReg baseReg,
                              const uint64_t addrOff)
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
                    if (ops[1].reg == addrReg)
                    {
                        copyOperands(out, consumer, ops);
                        out.ops[1].reg      = baseReg;
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

        bool buildAddrAmcRewrite(ConsumerRewrite& out,
                                 const MicroInstr& consumer,
                                 const MicroInstrOperand* ops,
                                 const MicroReg addrReg,
                                 const MicroReg baseReg,
                                 const MicroReg indexReg,
                                 const MicroOpBits addrBits,
                                 const uint64_t scale,
                                 const uint64_t add)
        {
            if (!ops)
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

        const MicroInstrRef consumerRef = ctx.nextRef(defRef);
        if (!consumerRef.isValid() || ctx.isClaimed(consumerRef))
            return false;

        const MicroInstr* consumer = ctx.instruction(consumerRef);
        if (!consumer)
            return false;

        ConsumerRewrite rewrite;
        if (!buildAddrRewrite(rewrite, *consumer, ctx.operandsFor(consumerRef), addrReg, baseReg, defOps[3].valueU64))
            return false;

        if (!ctx.claimAll({consumerRef}))
            return false;

        ctx.emitRewrite(consumerRef, rewrite.newOp, {rewrite.ops, rewrite.numOps}, rewrite.allocOps);
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

        const MicroInstrRef consumerRef = ctx.nextRef(defRef);
        if (!consumerRef.isValid() || ctx.isClaimed(consumerRef))
            return false;

        const MicroInstr* consumer = ctx.instruction(consumerRef);
        if (!consumer)
            return false;

        ConsumerRewrite rewrite;
        if (!buildAddrAmcRewrite(rewrite,
                                 *consumer,
                                 ctx.operandsFor(consumerRef),
                                 addrReg,
                                 defOps[1].reg,
                                 defOps[2].reg,
                                 defOps[4].opBits,
                                 defOps[5].valueU64,
                                 defOps[6].valueU64))
            return false;

        if (!ctx.claimAll({consumerRef}))
            return false;

        ctx.emitRewrite(consumerRef, rewrite.newOp, {rewrite.ops, rewrite.numOps}, rewrite.allocOps);
        return true;
    }
}

SWC_END_NAMESPACE();
