#include "pch.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstrInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t K_CFG_HASH_OFFSET_BASIS = 1469598103934665603ull;
    constexpr uint64_t K_CFG_HASH_PRIME        = 1099511628211ull;
    constexpr uint64_t K_CFG_HASH_INVALID_OPS  = std::numeric_limits<uint64_t>::max();
    constexpr uint32_t K_INVALID_INSTRUCTION_INDEX = std::numeric_limits<uint32_t>::max();

    template<typename T, size_t InlineCapacity>
    size_t smallVectorStorageReserved(const SmallVector<T, InlineCapacity>& values)
    {
        if (values.isInline())
            return 0;
        return values.capacity() * sizeof(T);
    }

    void mixControlFlowHash(uint64_t& inOutHash, uint64_t value)
    {
        inOutHash ^= value;
        inOutHash *= K_CFG_HASH_PRIME;
    }
}

void MicroControlFlowGraph::clear()
{
    instructionRefs_.clear();
    successors_.clear();
    hasUnsupportedControlFlowForCfgLiveness_ = false;
    supportsDeadCodeLiveness_                = true;
}

uint64_t MicroControlFlowGraph::computeHash(const MicroStorage& storage, const MicroOperandStorage& operands)
{
    uint64_t hash = K_CFG_HASH_OFFSET_BASIS;
    for (const MicroInstr& inst : storage.view())
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::Label:
            {
                mixControlFlowHash(hash, 1);
                const MicroInstrOperand* ops = inst.ops(operands);
                if (ops && inst.numOperands >= 1)
                    mixControlFlowHash(hash, ops[0].valueU64);
                else
                    mixControlFlowHash(hash, K_CFG_HASH_INVALID_OPS);
                break;
            }
            case MicroInstrOpcode::JumpCond:
            case MicroInstrOpcode::JumpCondImm:
            {
                mixControlFlowHash(hash, 2);
                const MicroInstrOperand* ops = inst.ops(operands);
                if (ops && inst.numOperands >= 3)
                {
                    mixControlFlowHash(hash, static_cast<uint64_t>(ops[0].cpuCond));
                    mixControlFlowHash(hash, ops[2].valueU64);
                }
                else
                {
                    mixControlFlowHash(hash, K_CFG_HASH_INVALID_OPS);
                }

                break;
            }
            case MicroInstrOpcode::JumpReg:
            {
                mixControlFlowHash(hash, 3);
                break;
            }
            case MicroInstrOpcode::Ret:
                mixControlFlowHash(hash, 4);
                break;
            default:
                if (MicroInstrInfo::isTerminatorInstruction(inst))
                {
                    mixControlFlowHash(hash, 5);
                    mixControlFlowHash(hash, static_cast<uint64_t>(inst.op));
                }
                else
                {
                    // Keep stream position stable while ignoring non-CFG op rewrites.
                    mixControlFlowHash(hash, 0);
                }
                break;
        }
    }

    return hash;
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
        if (inst.op == MicroInstrOpcode::JumpReg || inst.op == MicroInstrOpcode::JumpCondImm)
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

        if (inst->op == MicroInstrOpcode::Ret || inst->op == MicroInstrOpcode::JumpReg)
            continue;

        if (MicroInstrInfo::isTerminatorInstruction(*inst))
        {
            supportsDeadCodeLiveness_ = false;
            continue;
        }

        if (hasFallthrough)
            successors.push_back(static_cast<uint32_t>(instructionIndex + 1));
    }
}

SWC_END_NAMESPACE();
