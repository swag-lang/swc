#pragma once
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class MicroControlFlowGraph
{
public:
    uint32_t                               instructionCount() const { return static_cast<uint32_t>(instructionRefs_.size()); }
    std::span<const MicroInstrRef>         instructionRefs() const { return instructionRefs_; }
    std::span<const SmallVector<uint32_t>> successors() const { return successors_; }
    const SmallVector<uint32_t>&           successors(uint32_t instructionIndex) const { return successors_[instructionIndex]; }
    bool                                   hasUnsupportedControlFlowForCfgLiveness() const { return hasUnsupportedControlFlowForCfgLiveness_; }
    bool                                   supportsDeadCodeLiveness() const { return supportsDeadCodeLiveness_; }

private:
    void            clear();
    void            build(const MicroStorage& storage, const MicroOperandStorage& operands);
    static uint64_t computeHash(const MicroStorage& storage, const MicroOperandStorage& operands);

    std::vector<MicroInstrRef>         instructionRefs_;
    std::vector<SmallVector<uint32_t>> successors_;
    bool                               hasUnsupportedControlFlowForCfgLiveness_ = false;
    bool                               supportsDeadCodeLiveness_                = true;

    friend class MicroBuilder;
};

SWC_END_NAMESPACE();
