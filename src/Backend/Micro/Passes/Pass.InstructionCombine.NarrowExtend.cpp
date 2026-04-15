#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// Zero/sign extend whose upper bits are never read. Collapses to a plain
// LoadRegReg at srcBits, or an erase when dst == src.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        bool allUsesFitWithin(const MicroSsaState& ssa, const MicroStorage& storage, const MicroOperandStorage& operands, const MicroSsaState::ValueInfo& valueInfo, MicroReg reg, uint32_t maxBits)
        {
            for (const auto& useSite : valueInfo.uses)
            {
                if (useSite.kind != MicroSsaState::UseSite::Kind::Instruction)
                    return false;
                const MicroInstr* useInst = storage.ptr(useSite.instRef);
                if (!useInst)
                    return false;
                const MicroInstrOperand* useOps  = useInst->ops(operands);
                const MicroOpBits        useBits = useReadBits(*useInst, useOps, reg);
                if (useBits == MicroOpBits::Zero || getNumBits(useBits) > maxBits)
                    return false;
            }
            return true;
        }
    }

    bool tryNarrowExtend(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops)
            return false;

        const MicroReg    dst     = ops[0].reg;
        const MicroReg    src     = ops[1].reg;
        const MicroOpBits dstBits = ops[2].opBits;
        const MicroOpBits srcBits = ops[3].opBits;

        if (!dst.isVirtual() || dstBits == srcBits || srcBits == MicroOpBits::Zero)
            return false;

        uint32_t valueId = 0;
        if (!ctx.ssa->defValue(dst, ref, valueId))
            return false;

        const auto* valueInfo = ctx.ssa->valueInfo(valueId);
        if (!valueInfo || valueInfo->uses.empty())
            return false;

        if (!allUsesFitWithin(*ctx.ssa, *ctx.storage, *ctx.operands, *valueInfo, dst, getNumBits(srcBits)))
            return false;

        if (!ctx.claimAll({ref}))
            return false;

        if (dst == src)
        {
            ctx.emitErase(ref);
            return true;
        }

        MicroInstrOperand moveOps[3];
        moveOps[0].reg    = dst;
        moveOps[1].reg    = src;
        moveOps[2].opBits = srcBits;
        ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegReg, moveOps);
        return true;
    }
}

SWC_END_NAMESPACE();
