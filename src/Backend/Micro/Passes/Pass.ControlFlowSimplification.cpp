#include "pch.h"
#include "Backend/Micro/Passes/Pass.ControlFlowSimplification.h"
#include "Backend/Micro/MicroInstrInfo.h"

// Simplifies the micro CFG by removing structurally redundant control flow.
// Example: jmp L1; L1:          ->  <remove jump>.
// Example: dead block after ret ->  <remove unreachable instructions>.
// Example: unreferenced label   ->  <remove label>.

SWC_BEGIN_NAMESPACE();

namespace
{
    bool tryInvertCondition(MicroCond& outCond, MicroCond cond)
    {
        switch (cond)
        {
            case MicroCond::Equal:
            case MicroCond::Zero:
                outCond = MicroCond::NotEqual;
                return true;
            case MicroCond::NotEqual:
            case MicroCond::NotZero:
                outCond = MicroCond::Equal;
                return true;
            case MicroCond::Above:
                outCond = MicroCond::BelowOrEqual;
                return true;
            case MicroCond::AboveOrEqual:
                outCond = MicroCond::Below;
                return true;
            case MicroCond::Below:
                outCond = MicroCond::AboveOrEqual;
                return true;
            case MicroCond::BelowOrEqual:
            case MicroCond::NotAbove:
                outCond = MicroCond::Above;
                return true;
            case MicroCond::Greater:
                outCond = MicroCond::LessOrEqual;
                return true;
            case MicroCond::GreaterOrEqual:
                outCond = MicroCond::Less;
                return true;
            case MicroCond::Less:
                outCond = MicroCond::GreaterOrEqual;
                return true;
            case MicroCond::LessOrEqual:
                outCond = MicroCond::Greater;
                return true;
            case MicroCond::Overflow:
                outCond = MicroCond::NotOverflow;
                return true;
            case MicroCond::NotOverflow:
                outCond = MicroCond::Overflow;
                return true;
            case MicroCond::Parity:
            case MicroCond::EvenParity:
                outCond = MicroCond::NotParity;
                return true;
            case MicroCond::NotParity:
            case MicroCond::NotEvenParity:
                outCond = MicroCond::Parity;
                return true;
            default:
                return false;
        }
    }

    bool isJumpToImmediateNextLabel(const MicroInstrOperand* jumpOps, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, const MicroOperandStorage& operands)
    {
        SWC_ASSERT(jumpOps != nullptr);
        if (jumpOps[2].valueU64 > std::numeric_limits<Ref>::max())
            return false;

        const Ref targetLabelRef = static_cast<Ref>(jumpOps[2].valueU64);
        for (; scanIt != endIt; ++scanIt)
        {
            const MicroInstr& inst = *scanIt;
            if (inst.op == MicroInstrOpcode::Label)
            {
                const MicroInstrOperand* labelOps = inst.ops(operands);
                SWC_ASSERT(labelOps != nullptr);
                if (labelOps[0].valueU64 > std::numeric_limits<Ref>::max())
                    continue;

                if (static_cast<Ref>(labelOps[0].valueU64) == targetLabelRef)
                    return true;
                continue;
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

    bool tryMergeConditionalAndUnconditionalJump(const MicroInstr& conditionalJumpInst, const MicroInstr& unconditionalJumpInst, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, MicroOperandStorage& operands)
    {
        if (conditionalJumpInst.op != MicroInstrOpcode::JumpCond || unconditionalJumpInst.op != MicroInstrOpcode::JumpCond)
            return false;

        MicroInstrOperand* conditionalOps   = conditionalJumpInst.ops(operands);
        MicroInstrOperand* unconditionalOps = unconditionalJumpInst.ops(operands);
        if (!conditionalOps || !unconditionalOps)
            return false;

        if (conditionalOps[0].cpuCond == MicroCond::Unconditional || unconditionalOps[0].cpuCond != MicroCond::Unconditional)
            return false;

        if (conditionalOps[2].valueU64 > std::numeric_limits<Ref>::max() || unconditionalOps[2].valueU64 > std::numeric_limits<Ref>::max())
            return false;

        if (!isJumpToImmediateNextLabel(conditionalOps, scanIt, endIt, operands))
            return false;

        MicroCond invertedCond;
        if (!tryInvertCondition(invertedCond, conditionalOps[0].cpuCond))
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
    MicroStorage&            storage  = *SWC_NOT_NULL(context.instructions);
    MicroOperandStorage&     operands = *SWC_NOT_NULL(context.operands);
    const MicroStorage::View view     = storage.view();
    const auto               endIt    = view.end();
    const auto               beginIt  = view.begin();

    for (auto it = beginIt; it != endIt;)
    {
        const Ref         instRef = it.current;
        const MicroInstr& inst    = *it;
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
                    const Ref nextRef = it.current;
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

            const Ref deadRef = scanIt.current;
            ++scanIt;
            storage.erase(deadRef);
            changed = true;
        }
    }

    std::unordered_set<Ref> referencedLabels;
    referencedLabels.reserve(storage.count());
    collectReferencedLabels(storage, operands, referencedLabels);

    for (auto it = storage.view().begin(); it != storage.view().end();)
    {
        const Ref         instRef = it.current;
        const MicroInstr& inst    = *it;
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

    context.passChanged = changed;
    return Result::Continue;
}

SWC_END_NAMESPACE();
