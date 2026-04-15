#include "pch.h"
#include "Backend/Micro/MicroStorage.h"
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
                    if (ops[info.microOpIndex].microOp == MicroOp::CompareExchange)
                        modes[1] = MicroInstrRegMode::UseDef;
                    break;

                default:
                    break;
            }

            return modes;
        }
    }

    bool Context::isClaimed(MicroInstrRef ref) const
    {
        return claimed.contains(ref.get());
    }

    bool Context::claimAll(std::initializer_list<MicroInstrRef> refs)
    {
        for (const MicroInstrRef ref : refs)
            if (isClaimed(ref))
                return false;

        for (const MicroInstrRef ref : refs)
            claimed.insert(ref.get());
        return true;
    }

    void Context::emitErase(MicroInstrRef ref)
    {
        Action action;
        action.ref   = ref;
        action.erase = true;
        actions.push_back(action);
    }

    void Context::emitRewrite(MicroInstrRef ref, MicroInstrOpcode newOp, std::span<const MicroInstrOperand> newOps, bool allocNewBlock)
    {
        SWC_ASSERT(newOps.size() <= Action::K_MAX_OPS);

        Action action;
        action.ref      = ref;
        action.newOp    = newOp;
        action.numOps   = static_cast<uint8_t>(newOps.size());
        action.allocOps = allocNewBlock;
        for (size_t idx = 0; idx < newOps.size(); ++idx)
            action.ops[idx] = newOps[idx];

        actions.push_back(action);
    }

    const MicroInstr* Context::instruction(MicroInstrRef ref) const
    {
        SWC_ASSERT(storage != nullptr);
        return storage->ptr(ref);
    }

    const MicroInstrOperand* Context::operandsFor(MicroInstrRef ref) const
    {
        SWC_ASSERT(operands != nullptr);
        const MicroInstr* inst = instruction(ref);
        if (!inst)
            return nullptr;

        return inst->ops(*operands);
    }

    MicroInstrRef Context::nextRef(MicroInstrRef ref) const
    {
        SWC_ASSERT(storage != nullptr);
        return storage->findNextInstructionRef(ref);
    }

    void applyAction(const Context& ctx, const Action& action)
    {
        SWC_ASSERT(ctx.storage != nullptr);
        SWC_ASSERT(ctx.operands != nullptr);

        if (action.erase)
        {
            ctx.storage->erase(action.ref);
            return;
        }

        MicroInstr* inst = ctx.storage->ptr(action.ref);
        SWC_ASSERT(inst != nullptr);

        if (action.allocOps)
        {
            const auto [newRef, opsBlock] = ctx.operands->emplaceUninitArray(action.numOps);
            for (uint8_t idx = 0; idx < action.numOps; ++idx)
                opsBlock[idx] = action.ops[idx];
            inst->opsRef = newRef;
        }
        else if (action.numOps)
        {
            MicroInstrOperand* existingOps = inst->ops(*ctx.operands);
            SWC_ASSERT(existingOps != nullptr);
            for (uint8_t idx = 0; idx < action.numOps; ++idx)
                existingOps[idx] = action.ops[idx];
        }

        inst->op          = action.newOp;
        inst->numOperands = action.numOps;
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

    void PatternRegistry::add(MicroInstrOpcode op, PatternFn fn)
    {
        byOpcode[static_cast<size_t>(op)].push_back(fn);
    }

    std::span<const PatternFn> PatternRegistry::patternsFor(MicroInstrOpcode op) const
    {
        return byOpcode[static_cast<size_t>(op)].span();
    }
}

SWC_END_NAMESPACE();
