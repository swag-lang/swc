#pragma once
#include "Support/Core/RefTypes.h"
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

    // True iff the CFG contains a back-edge (a successor pointing to an
    // earlier-or-equal instruction index). A cycle, in any linear layout of
    // its nodes, must contain at least one such backward edge, so the absence
    // of any back-edge proves the function is loop-free. Loop-only passes
    // (e.g. LICM) use this to skip their dominator/loop analysis entirely.
    bool hasLoop() const { return hasLoop_; }

private:
    void            clear();
    void            build(const MicroStorage& storage, const MicroOperandStorage& operands);
    static uint64_t computeHash(const MicroStorage& storage, const MicroOperandStorage& operands);

    std::vector<MicroInstrRef> instructionRefs_;
    std::vector<EdgeList>      successors_;
    std::vector<EdgeList>      predecessors_;
    bool                       hasUnsupportedControlFlowForCfgLiveness_ = false;
    bool                       supportsDeadCodeLiveness_                = true;
    bool                       hasLoop_                                 = false;

    friend class MicroBuilder;
};

SWC_END_NAMESPACE();
