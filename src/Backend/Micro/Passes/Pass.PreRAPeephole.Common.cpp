#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/Passes/Pass.PreRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PreRaPeephole
{
    namespace
    {
        std::array<MicroInstrRegMode, 3> resolveRegModes(const MicroInstr& inst, const MicroInstrOperand* ops)
        {
            const MicroInstrDef& info  = MicroInstr::info(inst.op);
            auto                 modes = info.regModes;
            if (!ops)
                return modes;

            switch (info.special)
            {
                case MicroInstrRegSpecial::OpBinaryRegReg:
                    if (ops[info.microOpIndex].microOp == MicroOp::Exchange)
                    {
                        modes[0] = MicroInstrRegMode::UseDef;
                        modes[1] = MicroInstrRegMode::UseDef;
                    }
                    break;

                case MicroInstrRegSpecial::OpBinaryMemReg:
                    if (ops[info.microOpIndex].microOp == MicroOp::Exchange)
                        modes[1] = MicroInstrRegMode::UseDef;
                    break;

                case MicroInstrRegSpecial::OpTernaryRegRegReg:
                    break;

                default:
                    break;
            }

            return modes;
        }
    }

    bool Context::claimAll(std::initializer_list<MicroInstrRef> refs)
    {
        for (const MicroInstrRef ref : refs)
            if (isClaimed(ref) || isRelocated(ref))
                return false;

        for (const MicroInstrRef ref : refs)
            claimed.insert(ref.get());
        return true;
    }

    bool hasVirtualForbiddenPhysRegs(const Context& ctx, MicroReg reg)
    {
        if (!ctx.builder || !reg.isVirtual())
            return false;

        return ctx.builder->virtualRegForbiddenPhysRegs().contains(reg);
    }

    void mergeVirtualForbiddenRegs(const Context& ctx, const MicroReg fromReg, const MicroReg toReg)
    {
        if (!ctx.builder)
            return;

        ctx.builder->mergeVirtualRegForbiddenPhysRegs(fromReg, toReg);
    }

    bool buildUseOnlyRegRewrite(Action& outAction, const MicroInstr& consumer, const MicroInstrOperand* ops, const MicroReg fromReg, const MicroReg toReg)
    {
        if (!ops || consumer.numOperands > Action::K_MAX_OPS)
            return false;

        outAction.newOp  = consumer.op;
        outAction.numOps = consumer.numOperands;
        for (uint8_t idx = 0; idx < consumer.numOperands; ++idx)
            outAction.ops[idx] = ops[idx];

        bool       changed = false;
        const auto modes   = resolveRegModes(consumer, ops);
        for (size_t idx = 0; idx < modes.size() && idx < consumer.numOperands; ++idx)
        {
            if (modes[idx] != MicroInstrRegMode::Use)
                continue;
            if (outAction.ops[idx].reg != fromReg)
                continue;

            outAction.ops[idx].reg = toReg;
            changed                = true;
        }

        return changed;
    }

    uint64_t extendBits(const uint64_t value, const MicroOpBits srcBits, const MicroOpBits dstBits, const bool isSigned)
    {
        const uint64_t srcMask = getBitsMask(srcBits);
        uint64_t       masked  = value & srcMask;
        if (isSigned)
        {
            const uint32_t srcBitsNum = getNumBits(srcBits);
            const uint64_t signBit    = 1ULL << (srcBitsNum - 1);
            if (masked & signBit)
                masked |= ~srcMask;
        }

        return masked & getBitsMask(dstBits);
    }

    void setMaskedImmediateValue(MicroInstrOperand& op, const uint64_t value, const MicroOpBits bits)
    {
        op.setImmediateValue(ApInt(value & getBitsMask(bits), getNumBits(bits)));
    }
}

SWC_END_NAMESPACE();
