#include "pch.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstrInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_INVALID_INSTRUCTION_INDEX = std::numeric_limits<uint32_t>::max();
}

void MicroControlFlowGraph::clear()
{
    instructionRefs_.clear();
    successors_.clear();
    predecessors_.clear();
    hasUnsupportedControlFlowForCfgLiveness_ = false;
    supportsDeadCodeLiveness_                = true;
    hasLoop_                                 = false;
}

void MicroControlFlowGraph::build(const MicroStorage& storage, const MicroOperandStorage& operands)
{
    clear();

    const uint32_t instructionCount = storage.count();
    instructionRefs_.reserve(instructionCount);
    successors_.resize(instructionCount);
    std::vector<uint32_t> labelToInstructionIndex;
    labelToInstructionIndex.reserve(instructionCount / 4 + 1);

    for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
    {
        const uint32_t instructionIndex = static_cast<uint32_t>(instructionRefs_.size());
        instructionRefs_.push_back(it.current);
        const MicroInstr& inst = *it;
        if ((inst.op == MicroInstrOpcode::JumpReg && inst.numOperands < 2) || inst.op == MicroInstrOpcode::JumpCondImm)
            hasUnsupportedControlFlowForCfgLiveness_ = true;

        if (inst.op == MicroInstrOpcode::Label)
        {
            const MicroInstrOperand* labelOps = inst.ops(operands);
            if (!labelOps || labelOps[0].valueU64 > std::numeric_limits<uint32_t>::max())
            {
                supportsDeadCodeLiveness_ = false;
            }
            else
            {
                const uint32_t labelIndex = static_cast<uint32_t>(labelOps[0].valueU64);
                if (labelIndex >= labelToInstructionIndex.size())
                    labelToInstructionIndex.resize(labelIndex + 1, K_INVALID_INSTRUCTION_INDEX);
                labelToInstructionIndex[labelIndex] = instructionIndex;
            }
        }
    }

    for (size_t instructionIndex = 0; instructionIndex < instructionRefs_.size(); ++instructionIndex)
    {
        const MicroInstr* inst = storage.ptr(instructionRefs_[instructionIndex]);
        if (!inst)
        {
            supportsDeadCodeLiveness_ = false;
            continue;
        }

        auto&      successors     = successors_[instructionIndex];
        const bool hasFallthrough = instructionIndex + 1 < instructionRefs_.size();
        if (inst->op == MicroInstrOpcode::JumpCond || inst->op == MicroInstrOpcode::JumpCondImm)
        {
            const MicroInstrOperand* jumpOps = inst->ops(operands);
            if (!jumpOps || jumpOps[2].valueU64 > std::numeric_limits<uint32_t>::max())
            {
                supportsDeadCodeLiveness_ = false;
            }
            else
            {
                const uint32_t targetLabelIndex = static_cast<uint32_t>(jumpOps[2].valueU64);
                if (targetLabelIndex < labelToInstructionIndex.size() &&
                    labelToInstructionIndex[targetLabelIndex] != K_INVALID_INSTRUCTION_INDEX)
                {
                    successors.push_back(labelToInstructionIndex[targetLabelIndex]);
                }
                else
                {
                    supportsDeadCodeLiveness_ = false;
                }
            }

            if (!MicroInstrInfo::isUnconditionalJumpInstruction(*inst, jumpOps) && hasFallthrough)
            {
                const uint32_t fallthrough = static_cast<uint32_t>(instructionIndex + 1);
                if (successors.empty() || successors.back() != fallthrough)
                    successors.push_back(fallthrough);
            }

            continue;
        }

        if (inst->op == MicroInstrOpcode::JumpReg)
        {
            const MicroInstrOperand* jumpOps = inst->ops(operands);
            if (!jumpOps || inst->numOperands < 2)
                continue;

            for (uint8_t operandIndex = 1; operandIndex < inst->numOperands; ++operandIndex)
            {
                if (jumpOps[operandIndex].valueU64 > std::numeric_limits<uint32_t>::max())
                {
                    supportsDeadCodeLiveness_ = false;
                    continue;
                }

                const uint32_t targetLabelIndex = static_cast<uint32_t>(jumpOps[operandIndex].valueU64);
                if (targetLabelIndex >= labelToInstructionIndex.size() || labelToInstructionIndex[targetLabelIndex] == K_INVALID_INSTRUCTION_INDEX)
                {
                    supportsDeadCodeLiveness_ = false;
                    continue;
                }

                const uint32_t targetInstructionIndex = labelToInstructionIndex[targetLabelIndex];
                if (std::ranges::find(successors, targetInstructionIndex) == successors.end())
                    successors.push_back(targetInstructionIndex);
            }

            continue;
        }

        if (inst->op == MicroInstrOpcode::Ret)
            continue;

        if (MicroInstrInfo::isTerminatorInstruction(*inst))
        {
            supportsDeadCodeLiveness_ = false;
            continue;
        }

        if (hasFallthrough)
            successors.push_back(static_cast<uint32_t>(instructionIndex + 1));
    }

    // Build predecessors from successors, and detect back-edges along the way.
    // An edge whose target index is <= its source index points backward in the
    // instruction layout; a cycle requires at least one such edge, so this is a
    // sound (conservative) loop-presence test.
    predecessors_.resize(instructionRefs_.size());
    for (size_t idx = 0; idx < instructionRefs_.size(); ++idx)
    {
        for (const uint32_t succIdx : successors_[idx])
        {
            if (succIdx <= idx)
                hasLoop_ = true;
            if (succIdx < predecessors_.size())
                predecessors_[succIdx].push_back(static_cast<uint32_t>(idx));
        }
    }
}

SWC_END_NAMESPACE();
