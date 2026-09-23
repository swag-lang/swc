#pragma once
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/RefTypes.h"
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

    // Where one instruction sits in this graph. The refs are a dense list in program order, so
    // finding a reference in it means walking the function; the callers that ask do so once per
    // candidate they examine, which makes the search quadratic in the function. The table is
    // built on the first request and lives exactly as long as the graph it describes.
    static constexpr uint32_t K_NO_INDEX = std::numeric_limits<uint32_t>::max();
    uint32_t                  indexOf(MicroInstrRef ref) const;

    // Identifies this graph's contents. Every build takes a fresh value, so a reader that
    // derived something from the graph can tell whether that derivation still describes it -
    // even if a graph is destroyed and another is allocated at the same address.
    uint64_t buildId() const { return buildId_; }

private:
    void clear();
    void addEdge(uint32_t source, uint32_t target);
    void build(const MicroStorage& storage, const MicroOperandStorage& operands);

    std::vector<MicroInstrRef> instructionRefs_;
    mutable std::vector<uint32_t> indexBySlot_;
    uint64_t                      buildId_ = 0;
    std::vector<uint32_t>      labelToInstructionIndex_;
    std::vector<EdgeList>      successors_;
    std::vector<EdgeList>      predecessors_;
    bool                       hasUnsupportedControlFlowForCfgLiveness_ = false;
    bool                       supportsDeadCodeLiveness_                = true;
    bool                       hasLoop_                                 = false;

    friend class MicroBuilder;
};

SWC_END_NAMESPACE();
