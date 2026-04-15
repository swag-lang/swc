#include "pch.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
{
    namespace
    {
        bool isSelfCopyNoEffect(const MicroInstr& inst, const MicroInstrOperand* ops)
        {
            if (inst.op != MicroInstrOpcode::LoadRegReg || !ops)
                return false;

            if (ops[0].reg != ops[1].reg)
                return false;

            // "mov eax, eax" is not a no-op on x64 because it clears the upper
            // 32 bits of the parent register. Keep those copies intact.
            if (ops[0].reg.isAnyInt() && ops[2].opBits == MicroOpBits::B32)
                return false;

            return true;
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

    MicroInstrRef Context::previousRef(MicroInstrRef ref) const
    {
        SWC_ASSERT(storage != nullptr);
        return storage->findPreviousInstructionRef(ref);
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

    void PatternRegistry::add(MicroInstrOpcode op, PatternFn fn)
    {
        byOpcode[static_cast<size_t>(op)].push_back(fn);
    }

    std::span<const PatternFn> PatternRegistry::patternsFor(MicroInstrOpcode op) const
    {
        return byOpcode[static_cast<size_t>(op)].span();
    }

    bool isTriviallyErasableNoEffect(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        return inst.op == MicroInstrOpcode::Nop || isSelfCopyNoEffect(inst, ops);
    }

    bool instructionActuallyUsesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        const MicroInstrDef& info = MicroInstr::info(inst.op);
        if (!info.flags.has(MicroInstrFlagsE::UsesCpuFlags))
            return false;

        if ((inst.op == MicroInstrOpcode::JumpCond || inst.op == MicroInstrOpcode::JumpCondImm) &&
            ops &&
            ops[0].cpuCond == MicroCond::Unconditional)
            return false;

        return true;
    }

    bool isRedundantFallthroughJumpToNextLabel(const Context& ctx, MicroInstrRef ref, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (inst.op != MicroInstrOpcode::JumpCond || !ops)
            return false;

        const uint64_t targetLabel = ops[2].valueU64;
        for (MicroInstrRef scanRef = ctx.nextRef(ref); scanRef.isValid(); scanRef = ctx.nextRef(scanRef))
        {
            const MicroInstr* scanInst = ctx.instruction(scanRef);
            if (!scanInst)
                return false;

            const MicroInstrOperand* scanOps = scanInst->ops(*ctx.operands);
            if (scanInst->op == MicroInstrOpcode::Label)
            {
                if (scanOps && scanOps[0].valueU64 == targetLabel)
                    return true;

                continue;
            }

            if (isTriviallyErasableNoEffect(*scanInst, scanOps))
                continue;

            return false;
        }

        return false;
    }
}

SWC_END_NAMESPACE();
