#include "pch.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_INVALID_INSTRUCTION_INDEX = std::numeric_limits<uint32_t>::max();
}

uint32_t MicroControlFlowGraph::indexOf(const MicroInstrRef ref) const
{
    if (ref.isInvalid() || instructionRefs_.empty())
        return K_NO_INDEX;

    if (indexBySlot_.empty())
    {
        uint32_t maxSlot = 0;
        for (const MicroInstrRef instRef : instructionRefs_)
            maxSlot = std::max(maxSlot, instRef.get());

        indexBySlot_.assign(maxSlot + 1, K_NO_INDEX);
        for (uint32_t index = 0; index < instructionRefs_.size(); ++index)
            indexBySlot_[instructionRefs_[index].get()] = index;
    }

    const uint32_t slot = ref.get();
    return slot < indexBySlot_.size() ? indexBySlot_[slot] : K_NO_INDEX;
}

void MicroControlFlowGraph::clear()
{
    instructionRefs_.clear();
    indexBySlot_.clear();
    // Rebuilds keep overflow storage for high-fanout branches and joins.
    for (auto& edges : successors_)
        edges.clear();
    for (auto& edges : predecessors_)
        edges.clear();
    std::ranges::fill(labelToInstructionIndex_, K_INVALID_INSTRUCTION_INDEX);
    hasUnsupportedControlFlowForCfgLiveness_ = false;
    supportsDeadCodeLiveness_                = true;
    hasLoop_                                 = false;
}

void MicroControlFlowGraph::addEdge(const uint32_t source, const uint32_t target)
{
    SWC_ASSERT(source < successors_.size());
    SWC_ASSERT(target < predecessors_.size());
    successors_[source].push_back(target);
    predecessors_[target].push_back(source);
    // A cycle requires an edge pointing backward in instruction order.
    if (target <= source)
        hasLoop_ = true;
}

void MicroControlFlowGraph::build(const MicroStorage& storage, const MicroOperandStorage& operands)
{
    clear();

    const uint32_t instructionCount = storage.count();
    instructionRefs_.reserve(instructionCount);
    successors_.resize(instructionCount);
    predecessors_.resize(instructionCount);
    labelToInstructionIndex_.reserve(instructionCount / 4 + 1);

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
                if (labelIndex >= labelToInstructionIndex_.size())
                    labelToInstructionIndex_.resize(labelIndex + 1, K_INVALID_INSTRUCTION_INDEX);
                labelToInstructionIndex_[labelIndex] = instructionIndex;
            }
        }
    }

    for (uint32_t instructionIndex = 0; instructionIndex < instructionRefs_.size(); ++instructionIndex)
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
                if (targetLabelIndex < labelToInstructionIndex_.size() &&
                    labelToInstructionIndex_[targetLabelIndex] != K_INVALID_INSTRUCTION_INDEX)
                {
                    addEdge(instructionIndex, labelToInstructionIndex_[targetLabelIndex]);
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
                    addEdge(instructionIndex, fallthrough);
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
                if (targetLabelIndex >= labelToInstructionIndex_.size() || labelToInstructionIndex_[targetLabelIndex] == K_INVALID_INSTRUCTION_INDEX)
                {
                    supportsDeadCodeLiveness_ = false;
                    continue;
                }

                const uint32_t targetInstructionIndex = labelToInstructionIndex_[targetLabelIndex];
                // Sources are visited in order, so an edge already added by this
                // instruction is the target's last predecessor.
                const auto& targetPredecessors = predecessors_[targetInstructionIndex];
                if (targetPredecessors.empty() || targetPredecessors.back() != instructionIndex)
                    addEdge(instructionIndex, targetInstructionIndex);
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
            addEdge(instructionIndex, instructionIndex + 1);
    }
}

SWC_END_NAMESPACE();
