#include "pch.h"
#include "Backend/Micro/Passes/Pass.PreRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PreRaPeephole
{
    namespace
    {
        struct ConstantProducer
        {
            MicroReg reg           = MicroReg::invalid();
            uint64_t value         = 0;
            bool     preferPtrLoad = false;
        };

        struct ConsumerRewrite
        {
            MicroInstrOpcode  newOp                  = MicroInstrOpcode::Nop;
            uint8_t           numOps                 = 0;
            MicroInstrOperand ops[Action::K_MAX_OPS] = {};
        };

        bool getConstantProducer(ConstantProducer& out, const MicroInstr& defInst, const MicroInstrOperand* defOps)
        {
            if (!defOps)
                return false;

            switch (defInst.op)
            {
                case MicroInstrOpcode::LoadRegImm:
                    if (defOps[2].hasWideImmediateValue())
                        return false;
                    out.reg   = defOps[0].reg;
                    out.value = defOps[2].valueU64;
                    return out.reg.isVirtualInt();

                case MicroInstrOpcode::LoadRegPtrImm:
                    out.reg           = defOps[0].reg;
                    out.value         = defOps[2].valueU64;
                    out.preferPtrLoad = true;
                    return out.reg.isVirtualInt();

                case MicroInstrOpcode::ClearReg:
                    out.reg   = defOps[0].reg;
                    out.value = 0;
                    return out.reg.isVirtualInt();

                default:
                    return false;
            }
        }

        void emitLoadRegConstant(ConsumerRewrite& out, const MicroReg dst, const MicroOpBits bits, const uint64_t value, const bool preferPtrLoad)
        {
            if (preferPtrLoad && bits == MicroOpBits::B64)
            {
                out.newOp           = MicroInstrOpcode::LoadRegPtrImm;
                out.numOps          = 3;
                out.ops[0].reg      = dst;
                out.ops[1].opBits   = MicroOpBits::B64;
                out.ops[2].valueU64 = value;
                return;
            }

            out.newOp         = MicroInstrOpcode::LoadRegImm;
            out.numOps        = 3;
            out.ops[0].reg    = dst;
            out.ops[1].opBits = bits;
            setMaskedImmediateValue(out.ops[2], value, bits);
        }

        void emitAddressConstant(ConsumerRewrite& out, const MicroReg dst, const MicroOpBits bits, const uint64_t value)
        {
            if (bits == MicroOpBits::B64)
            {
                out.newOp           = MicroInstrOpcode::LoadRegPtrImm;
                out.numOps          = 3;
                out.ops[0].reg      = dst;
                out.ops[1].opBits   = MicroOpBits::B64;
                out.ops[2].valueU64 = value;
                return;
            }

            emitLoadRegConstant(out, dst, bits, value, false);
        }

        bool buildSimpleImmediateRewrite(ConsumerRewrite& out, const MicroInstr& consumer, const MicroInstrOperand* ops, const ConstantProducer& producer)
        {
            switch (consumer.op)
            {
                case MicroInstrOpcode::LoadMemReg:
                    if (ops[1].reg == producer.reg)
                    {
                        out.newOp           = MicroInstrOpcode::LoadMemImm;
                        out.numOps          = 4;
                        out.ops[0].reg      = ops[0].reg;
                        out.ops[1].opBits   = ops[2].opBits;
                        out.ops[2].valueU64 = ops[3].valueU64;
                        setMaskedImmediateValue(out.ops[3], producer.value, ops[2].opBits);
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::CmpRegReg:
                    if (ops[1].reg == producer.reg)
                    {
                        out.newOp         = MicroInstrOpcode::CmpRegImm;
                        out.numOps        = 3;
                        out.ops[0].reg    = ops[0].reg;
                        out.ops[1].opBits = ops[2].opBits;
                        setMaskedImmediateValue(out.ops[2], producer.value, ops[2].opBits);
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::CmpMemReg:
                    if (ops[1].reg == producer.reg)
                    {
                        out.newOp           = MicroInstrOpcode::CmpMemImm;
                        out.numOps          = 4;
                        out.ops[0].reg      = ops[0].reg;
                        out.ops[1].opBits   = ops[2].opBits;
                        out.ops[2].valueU64 = ops[3].valueU64;
                        setMaskedImmediateValue(out.ops[3], producer.value, ops[2].opBits);
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::OpBinaryRegReg:
                    if (ops[1].reg == producer.reg && ops[3].microOp != MicroOp::Exchange)
                    {
                        out.newOp          = MicroInstrOpcode::OpBinaryRegImm;
                        out.numOps         = 4;
                        out.ops[0].reg     = ops[0].reg;
                        out.ops[1].opBits  = ops[2].opBits;
                        out.ops[2].microOp = ops[3].microOp;
                        setMaskedImmediateValue(out.ops[3], producer.value, ops[2].opBits);
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::OpBinaryMemReg:
                    if (ops[1].reg == producer.reg && ops[3].microOp != MicroOp::Exchange)
                    {
                        out.newOp           = MicroInstrOpcode::OpBinaryMemImm;
                        out.numOps          = 5;
                        out.ops[0].reg      = ops[0].reg;
                        out.ops[1].opBits   = ops[2].opBits;
                        out.ops[2].microOp  = ops[3].microOp;
                        out.ops[3].valueU64 = ops[4].valueU64;
                        setMaskedImmediateValue(out.ops[4], producer.value, ops[2].opBits);
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadRegReg:
                    if (ops[1].reg == producer.reg)
                    {
                        emitLoadRegConstant(out, ops[0].reg, ops[2].opBits, producer.value, producer.preferPtrLoad);
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadAmcMemReg:
                    if (ops[2].reg == producer.reg)
                    {
                        out.newOp           = MicroInstrOpcode::LoadAmcMemImm;
                        out.numOps          = 8;
                        out.ops[0].reg      = ops[0].reg;
                        out.ops[1].reg      = ops[1].reg;
                        out.ops[3].opBits   = ops[3].opBits;
                        out.ops[4].opBits   = ops[4].opBits;
                        out.ops[5].valueU64 = ops[5].valueU64;
                        out.ops[6].valueU64 = ops[6].valueU64;
                        setMaskedImmediateValue(out.ops[7], producer.value, ops[4].opBits);
                        return true;
                    }
                    return false;

                default:
                    return false;
            }
        }

        bool buildExtendRewrite(ConsumerRewrite& out, const MicroInstr& consumer, const MicroInstrOperand* ops, const ConstantProducer& producer)
        {
            if (!ops || ops[1].reg != producer.reg)
                return false;

            if (consumer.op != MicroInstrOpcode::LoadSignedExtRegReg &&
                consumer.op != MicroInstrOpcode::LoadZeroExtRegReg)
                return false;

            const bool     isSigned = consumer.op == MicroInstrOpcode::LoadSignedExtRegReg;
            const uint64_t extended = extendBits(producer.value, ops[3].opBits, ops[2].opBits, isSigned);
            emitLoadRegConstant(out, ops[0].reg, ops[2].opBits, extended, false);
            return true;
        }

        bool buildAddressConstantRewrite(ConsumerRewrite& out, const MicroInstr& consumer, const MicroInstrOperand* ops, const ConstantProducer& producer)
        {
            switch (consumer.op)
            {
                case MicroInstrOpcode::LoadAddrRegMem:
                    if (ops[1].reg == producer.reg)
                    {
                        emitAddressConstant(out, ops[0].reg, ops[2].opBits, producer.value + ops[3].valueU64);
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadAmcRegMem:
                    if (ops[2].reg == producer.reg && ops[1].reg.isAnyInt())
                    {
                        out.newOp           = MicroInstrOpcode::LoadRegMem;
                        out.numOps          = 4;
                        out.ops[0].reg      = ops[0].reg;
                        out.ops[1].reg      = ops[1].reg;
                        out.ops[2].opBits   = ops[3].opBits;
                        out.ops[3].valueU64 = ops[6].valueU64 + producer.value * ops[5].valueU64;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadAmcMemReg:
                    if (ops[1].reg == producer.reg && ops[0].reg.isAnyInt())
                    {
                        out.newOp           = MicroInstrOpcode::LoadMemReg;
                        out.numOps          = 4;
                        out.ops[0].reg      = ops[0].reg;
                        out.ops[1].reg      = ops[2].reg;
                        out.ops[2].opBits   = ops[4].opBits;
                        out.ops[3].valueU64 = ops[6].valueU64 + producer.value * ops[5].valueU64;
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadAmcMemImm:
                    if (ops[1].reg == producer.reg && ops[0].reg.isAnyInt())
                    {
                        out.newOp           = MicroInstrOpcode::LoadMemImm;
                        out.numOps          = 4;
                        out.ops[0].reg      = ops[0].reg;
                        out.ops[1].opBits   = ops[4].opBits;
                        out.ops[2].valueU64 = ops[6].valueU64 + producer.value * ops[5].valueU64;
                        out.ops[3]          = ops[7];
                        return true;
                    }
                    return false;

                case MicroInstrOpcode::LoadAddrAmcRegMem:
                    if (ops[2].reg == producer.reg)
                    {
                        const uint64_t offset = ops[6].valueU64 + producer.value * ops[5].valueU64;
                        if (ops[1].reg.isAnyInt())
                        {
                            out.newOp           = MicroInstrOpcode::LoadAddrRegMem;
                            out.numOps          = 4;
                            out.ops[0].reg      = ops[0].reg;
                            out.ops[1].reg      = ops[1].reg;
                            out.ops[2].opBits   = ops[3].opBits;
                            out.ops[3].valueU64 = offset;
                            return true;
                        }

                        if (ops[1].reg.isNoBase())
                        {
                            emitAddressConstant(out, ops[0].reg, ops[3].opBits, offset);
                            return true;
                        }
                    }
                    return false;

                default:
                    return false;
            }
        }

        bool buildRewrite(ConsumerRewrite& out, const MicroInstr& consumer, const MicroInstrOperand* ops, const ConstantProducer& producer)
        {
            if (!ops)
                return false;

            if (buildSimpleImmediateRewrite(out, consumer, ops, producer))
                return true;
            if (buildExtendRewrite(out, consumer, ops, producer))
                return true;
            if (buildAddressConstantRewrite(out, consumer, ops, producer))
                return true;

            return false;
        }
    }

    bool tryForwardConstantLike(Context& ctx, const MicroInstrRef defRef, const MicroInstr& defInst)
    {
        if (ctx.isClaimed(defRef))
            return false;

        const MicroInstrOperand* defOps = defInst.ops(*ctx.operands);
        ConstantProducer         producer;
        if (!getConstantProducer(producer, defInst, defOps))
            return false;

        const MicroInstrRef consumerRef = ctx.nextRef(defRef);
        if (!consumerRef.isValid() || ctx.isClaimed(consumerRef))
            return false;

        const MicroInstr* consumer = ctx.instruction(consumerRef);
        if (!consumer)
            return false;

        ConsumerRewrite rewrite;
        if (!buildRewrite(rewrite, *consumer, ctx.operandsFor(consumerRef), producer))
            return false;

        if (!ctx.claimAll({consumerRef}))
            return false;

        const std::span rewrittenOps(rewrite.ops, rewrite.numOps);
        ctx.emitRewrite(consumerRef, rewrite.newOp, rewrittenOps);
        return true;
    }
}

SWC_END_NAMESPACE();
