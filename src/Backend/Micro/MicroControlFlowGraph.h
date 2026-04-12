#pragma once
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class MicroControlFlowGraph
{
public:
    using EdgeList = SmallVector<uint32_t, 2>;

    uint32_t                       instructionCount() const { return static_cast<uint32_t>(instructionRefs_.size()); }
    std::span<const MicroInstrRef> instructionRefs() const { return instructionRefs_; }
    std::span<const EdgeList>      successors() const { return successors_; }
    const EdgeList&                successors(uint32_t instructionIndex) const { return successors_[instructionIndex]; }
    std::span<const EdgeList>      predecessors() const { return predecessors_; }
    const EdgeList&                predecessors(uint32_t instructionIndex) const { return predecessors_[instructionIndex]; }
    bool                           hasUnsupportedControlFlowForCfgLiveness() const { return hasUnsupportedControlFlowForCfgLiveness_; }
    bool                           supportsDeadCodeLiveness() const { return supportsDeadCodeLiveness_; }

private:
    void            clear();
    void            build(const MicroStorage& storage, const MicroOperandStorage& operands);
    static uint64_t computeHash(const MicroStorage& storage, const MicroOperandStorage& operands);

    std::vector<MicroInstrRef> instructionRefs_;
    std::vector<EdgeList>      successors_;
    std::vector<EdgeList>      predecessors_;
    bool                       hasUnsupportedControlFlowForCfgLiveness_ = false;
    bool                       supportsDeadCodeLiveness_                = true;

    friend class MicroBuilder;
};

SWC_END_NAMESPACE();
