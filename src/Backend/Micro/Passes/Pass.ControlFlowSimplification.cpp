#include "pch.h"
#include "Backend/Micro/Passes/Pass.ControlFlowSimplification.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"

// Simplifies the micro CFG by removing structurally redundant control flow.
// Example: jmp L1; L1:          ->  <remove jump>.
// Example: dead block after ret ->  <remove unreachable instructions>.
// Example: unreferenced label   ->  <remove label>.

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isJumpToImmediateNextLabel(const MicroInstrOperand* jumpOps, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, const MicroOperandStorage& operands)
    {
        SWC_ASSERT(jumpOps != nullptr);
        if (jumpOps[2].valueU64 > std::numeric_limits<uint32_t>::max())
            return false;

        const MicroLabelRef targetLabelRef(static_cast<uint32_t>(jumpOps[2].valueU64));
        for (; scanIt != endIt; ++scanIt)
        {
            const MicroInstr& inst = *scanIt;
            if (inst.op == MicroInstrOpcode::Label)
            {
                const MicroInstrOperand* labelOps = inst.ops(operands);
                SWC_ASSERT(labelOps != nullptr);
                if (labelOps[0].valueU64 > std::numeric_limits<uint32_t>::max())
                    continue;

                if (MicroLabelRef(static_cast<uint32_t>(labelOps[0].valueU64)) == targetLabelRef)
                    return true;
                continue;
            }

            return false;
        }

        return false;
    }

    bool tryMergeConditionalAndUnconditionalJump(const MicroInstr& conditionalJumpInst, const MicroInstr& unconditionalJumpInst, const MicroStorage::Iterator& scanIt, const MicroStorage::Iterator& endIt, MicroOperandStorage& operands)
    {
        if (conditionalJumpInst.op != MicroInstrOpcode::JumpCond || unconditionalJumpInst.op != MicroInstrOpcode::JumpCond)
            return false;

        MicroInstrOperand*       conditionalOps   = conditionalJumpInst.ops(operands);
        const MicroInstrOperand* unconditionalOps = unconditionalJumpInst.ops(operands);
        if (!conditionalOps || !unconditionalOps)
            return false;

        if (conditionalOps[0].cpuCond == MicroCond::Unconditional || unconditionalOps[0].cpuCond != MicroCond::Unconditional)
            return false;

        if (conditionalOps[2].valueU64 > std::numeric_limits<uint32_t>::max() || unconditionalOps[2].valueU64 > std::numeric_limits<uint32_t>::max())
            return false;

        if (!isJumpToImmediateNextLabel(conditionalOps, scanIt, endIt, operands))
            return false;

        MicroCond invertedCond;
        if (!MicroPassHelpers::tryInvertCondition(invertedCond, conditionalOps[0].cpuCond))
            return false;

        conditionalOps[0].cpuCond  = invertedCond;
        conditionalOps[2].valueU64 = unconditionalOps[2].valueU64;
        return true;
    }
}

Result MicroControlFlowSimplificationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool                     changed  = false;
    MicroStorage&            storage  = *context.instructions;
    MicroOperandStorage&     operands = *context.operands;
    const MicroStorage::View view     = storage.view();
    const auto               endIt    = view.end();
    const auto               beginIt  = view.begin();

    for (auto it = beginIt; it != endIt;)
    {
        const MicroInstrRef instRef = it.current;
        const MicroInstr&   inst    = *it;
        ++it;

        if (inst.op == MicroInstrOpcode::JumpCond)
        {
            const MicroInstrOperand* jumpOps = inst.ops(operands);
            SWC_ASSERT(jumpOps != nullptr);

            if (it != endIt)
            {
                const MicroInstr& nextInst = *it;
                auto              scanIt   = it;
                ++scanIt;
                if (tryMergeConditionalAndUnconditionalJump(inst, nextInst, scanIt, endIt, operands))
                {
                    const MicroInstrRef nextRef = it.current;
                    ++it;
                    storage.erase(nextRef);
                    changed = true;
                    continue;
                }
            }

            if (isJumpToImmediateNextLabel(jumpOps, it, endIt, operands))
            {
                storage.erase(instRef);
                changed = true;
                continue;
            }
        }

        if (inst.op != MicroInstrOpcode::Ret && !MicroInstrInfo::isUnconditionalJumpInstruction(inst, inst.ops(operands)))
            continue;

        auto scanIt = it;
        while (scanIt != endIt)
        {
            if (scanIt->op == MicroInstrOpcode::Label)
                break;

            const MicroInstrRef deadRef = scanIt.current;
            ++scanIt;
            storage.erase(deadRef);
            changed = true;
        }
    }

    referencedLabels_.clear();
    referencedLabels_.reserve(storage.count());
    MicroPassHelpers::collectReferencedLabels(storage, operands, referencedLabels_, false);

    for (auto it = storage.view().begin(); it != storage.view().end();)
    {
        const MicroInstrRef instRef = it.current;
        const MicroInstr&   inst    = *it;
        ++it;

        if (inst.op != MicroInstrOpcode::Label)
            continue;

        const MicroInstrOperand* ops = inst.ops(operands);
        if (!ops || ops[0].valueU64 > std::numeric_limits<uint32_t>::max())
            continue;

        const MicroLabelRef labelRef(static_cast<uint32_t>(ops[0].valueU64));
        if (referencedLabels_.contains(labelRef))
            continue;

        storage.erase(instRef);
        changed = true;
    }

    context.passChanged = changed;
    return Result::Continue;
}

SWC_END_NAMESPACE();
