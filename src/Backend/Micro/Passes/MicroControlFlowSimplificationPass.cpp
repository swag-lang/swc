#include "pch.h"
#include "Backend/Micro/Passes/MicroControlFlowSimplificationPass.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isUnconditionalJump(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (!ops)
            return false;

        if (inst.op == MicroInstrOpcode::JumpCond || inst.op == MicroInstrOpcode::JumpCondImm)
            return ops[0].cpuCond == MicroCond::Unconditional;
        if (inst.op == MicroInstrOpcode::JumpReg || inst.op == MicroInstrOpcode::JumpTable)
            return true;
        return false;
    }

    bool isJumpToImmediateNextLabel(const MicroStorage& storage, const MicroOperandStorage& operands, Ref jumpRef)
    {
        for (auto jumpIt = storage.view().begin(); jumpIt != storage.view().end(); ++jumpIt)
        {
            if (jumpIt.current != jumpRef)
                continue;

            const MicroInstr& jumpInst = *jumpIt;
            if (jumpInst.op != MicroInstrOpcode::JumpCond)
                return false;

            const MicroInstrOperand* jumpOps = jumpInst.ops(operands);
            SWC_ASSERT(jumpOps != nullptr);
            SWC_ASSERT(jumpOps[2].valueU64 <= std::numeric_limits<Ref>::max());
            const Ref targetLabelRef = static_cast<Ref>(jumpOps[2].valueU64);

            auto scanIt = jumpIt;
            ++scanIt;
            for (; scanIt != storage.view().end(); ++scanIt)
            {
                const MicroInstr& inst = *scanIt;
                if (inst.op == MicroInstrOpcode::Debug)
                    continue;

                if (inst.op == MicroInstrOpcode::Label)
                {
                    const MicroInstrOperand* labelOps = inst.ops(operands);
                    SWC_ASSERT(labelOps != nullptr);
                    if (labelOps[0].valueU64 <= std::numeric_limits<Ref>::max() && static_cast<Ref>(labelOps[0].valueU64) == targetLabelRef)
                        return true;
                    continue;
                }

                return false;
            }

            return false;
        }

        return false;
    }

    void collectReferencedLabels(const MicroStorage& storage, const MicroOperandStorage& operands, std::unordered_set<Ref>& outLabels)
    {
        outLabels.clear();
        for (const MicroInstr& inst : storage.view())
        {
            if (inst.op != MicroInstrOpcode::JumpCond)
                continue;

            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops || ops[2].valueU64 > std::numeric_limits<Ref>::max())
                continue;

            outLabels.insert(static_cast<Ref>(ops[2].valueU64));
        }
    }
}

bool MicroControlFlowSimplificationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool                 changed  = false;
    MicroStorage&        storage  = *SWC_CHECK_NOT_NULL(context.instructions);
    MicroOperandStorage& operands = *SWC_CHECK_NOT_NULL(context.operands);

    for (auto it = storage.view().begin(); it != storage.view().end();)
    {
        const Ref   instRef = it.current;
        MicroInstr& inst    = *it;
        ++it;

        if (inst.op == MicroInstrOpcode::JumpCond && isJumpToImmediateNextLabel(storage, operands, instRef))
        {
            storage.erase(instRef);
            changed = true;
            continue;
        }

        if (inst.op != MicroInstrOpcode::Ret && !isUnconditionalJump(inst, inst.ops(operands)))
            continue;

        auto scanIt = it;
        for (; scanIt != storage.view().end();)
        {
            if (scanIt->op == MicroInstrOpcode::Label)
                break;

            const Ref deadRef = scanIt.current;
            ++scanIt;
            storage.erase(deadRef);
            changed = true;
        }
    }

    std::unordered_set<Ref> referencedLabels;
    collectReferencedLabels(storage, operands, referencedLabels);

    for (auto it = storage.view().begin(); it != storage.view().end();)
    {
        const Ref   instRef = it.current;
        MicroInstr& inst    = *it;
        ++it;

        if (inst.op != MicroInstrOpcode::Label)
            continue;

        const MicroInstrOperand* ops = inst.ops(operands);
        if (!ops || ops[0].valueU64 > std::numeric_limits<Ref>::max())
            continue;

        const Ref labelRef = static_cast<Ref>(ops[0].valueU64);
        if (referencedLabels.contains(labelRef))
            continue;

        storage.erase(instRef);
        changed = true;
    }

    return changed;
}

SWC_END_NAMESPACE();
