#include "pch.h"
#include "Backend/Micro/Passes/Pass.PreRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PreRaPeephole
{
    namespace
    {
        struct ConsumerRewrite
        {
            MicroInstrOpcode  newOp                  = MicroInstrOpcode::Nop;
            uint8_t           numOps                 = 0;
            MicroInstrOperand ops[Action::K_MAX_OPS] = {};
        };

        bool buildRewrite(ConsumerRewrite& out, const MicroInstr& consumer, const MicroInstrOperand* ops, MicroReg immReg, uint64_t imm)
        {
            if (!ops)
                return false;

            switch (consumer.op)
            {
                case MicroInstrOpcode::LoadMemReg:
                {
                    if (consumer.numOperands < 4 || ops[1].reg != immReg)
                        return false;

                    const MicroOpBits bits = ops[2].opBits;
                    out.newOp              = MicroInstrOpcode::LoadMemImm;
                    out.numOps             = 4;
                    out.ops[0].reg         = ops[0].reg;
                    out.ops[1].opBits      = bits;
                    out.ops[2].valueU64    = ops[3].valueU64;
                    out.ops[3].setImmediateValue(ApInt(imm & getBitsMask(bits), getNumBits(bits)));
                    return true;
                }

                case MicroInstrOpcode::CmpRegReg:
                {
                    if (consumer.numOperands < 3 || ops[1].reg != immReg)
                        return false;

                    const MicroOpBits bits = ops[2].opBits;
                    out.newOp              = MicroInstrOpcode::CmpRegImm;
                    out.numOps             = 3;
                    out.ops[0].reg         = ops[0].reg;
                    out.ops[1].opBits      = bits;
                    out.ops[2].setImmediateValue(ApInt(imm & getBitsMask(bits), getNumBits(bits)));
                    return true;
                }

                case MicroInstrOpcode::CmpMemReg:
                {
                    if (consumer.numOperands < 4 || ops[1].reg != immReg)
                        return false;

                    const MicroOpBits bits = ops[2].opBits;
                    out.newOp              = MicroInstrOpcode::CmpMemImm;
                    out.numOps             = 4;
                    out.ops[0].reg         = ops[0].reg;
                    out.ops[1].opBits      = bits;
                    out.ops[2].valueU64    = ops[3].valueU64;
                    out.ops[3].setImmediateValue(ApInt(imm & getBitsMask(bits), getNumBits(bits)));
                    return true;
                }

                case MicroInstrOpcode::OpBinaryRegReg:
                {
                    if (consumer.numOperands < 4 || ops[1].reg != immReg || ops[3].microOp == MicroOp::Exchange)
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

                case MicroInstrOpcode::OpBinaryMemReg:
                {
                    if (consumer.numOperands < 5 || ops[1].reg != immReg || ops[3].microOp == MicroOp::Exchange)
                        return false;

                    const MicroOpBits bits = ops[2].opBits;
                    out.newOp              = MicroInstrOpcode::OpBinaryMemImm;
                    out.numOps             = 5;
                    out.ops[0].reg         = ops[0].reg;
                    out.ops[1].opBits      = bits;
                    out.ops[2].microOp     = ops[3].microOp;
                    out.ops[3].valueU64    = ops[4].valueU64;
                    out.ops[4].setImmediateValue(ApInt(imm & getBitsMask(bits), getNumBits(bits)));
                    return true;
                }

                case MicroInstrOpcode::LoadRegReg:
                {
                    if (consumer.numOperands < 3 || ops[1].reg != immReg)
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
        if (defInst.op != MicroInstrOpcode::LoadRegImm || defInst.numOperands < 3 || ctx.isClaimed(defRef))
            return false;

        const MicroInstrOperand* defOps = defInst.ops(*ctx.operands);
        if (!defOps || defOps[2].hasWideImmediateValue())
            return false;

        const MicroReg immReg = defOps[0].reg;
        if (!immReg.isVirtualInt())
            return false;

        const MicroInstrRef consumerRef = ctx.nextRef(defRef);
        if (!consumerRef.isValid() || ctx.isClaimed(consumerRef))
            return false;

        const MicroInstr* consumer = ctx.instruction(consumerRef);
        if (!consumer)
            return false;

        ConsumerRewrite rewrite;
        if (!buildRewrite(rewrite, *consumer, ctx.operandsFor(consumerRef), immReg, defOps[2].valueU64))
            return false;

        if (!ctx.claimAll({consumerRef}))
            return false;

        ctx.emitRewrite(consumerRef, rewrite.newOp, {rewrite.ops, rewrite.numOps});
        return true;
    }
}

SWC_END_NAMESPACE();
