#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroSsaState.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_INVALID_INDEX       = std::numeric_limits<uint32_t>::max();
    constexpr uint32_t K_INVALID_BLOCK_INDEX = std::numeric_limits<uint32_t>::max();

    template<uint32_t N>
    void appendUniqueIndex(SmallVector<uint32_t, N>& values, const uint32_t value)
    {
        for (const uint32_t existing : values)
        {
            if (existing == value)
                return;
        }

        values.push_back(value);
    }

    uint32_t intersectIdom(uint32_t                     lhs,
                           uint32_t                     rhs,
                           const std::vector<uint32_t>& idom,
                           const std::vector<uint32_t>& rpoPosition)
    {
        uint32_t fingerLhs = lhs;
        uint32_t fingerRhs = rhs;
        while (fingerLhs != fingerRhs)
        {
            if (fingerLhs == K_INVALID_BLOCK_INDEX || fingerRhs == K_INVALID_BLOCK_INDEX)
                return K_INVALID_BLOCK_INDEX;

            const uint32_t posLhs = rpoPosition[fingerLhs];
            const uint32_t posRhs = rpoPosition[fingerRhs];
            if (posLhs == K_INVALID_INDEX || posRhs == K_INVALID_INDEX)
                return K_INVALID_BLOCK_INDEX;

            while (rpoPosition[fingerLhs] > rpoPosition[fingerRhs])
            {
                const uint32_t next = idom[fingerLhs];
                if (next == fingerLhs)
                    return K_INVALID_BLOCK_INDEX;
                fingerLhs = next;
            }

            while (rpoPosition[fingerRhs] > rpoPosition[fingerLhs])
            {
                const uint32_t next = idom[fingerRhs];
                if (next == fingerRhs)
                    return K_INVALID_BLOCK_INDEX;
                fingerRhs = next;
            }
        }

        return fingerLhs;
    }
}

bool MicroSsaState::isTrackedReg(const MicroReg reg)
{
    return reg.isVirtual();
}

uint32_t MicroSsaState::findRegValue(const std::span<const RegValueEntry> entries, const MicroReg reg)
{
    for (const RegValueEntry& entry : entries)
    {
        if (entry.reg == reg)
            return entry.valueId;
    }

    return K_INVALID_VALUE;
}

void MicroSsaState::build(MicroBuilder& builder, MicroStorage& storage, MicroOperandStorage& operands, const Encoder* encoder)
{
    clear();

    builder_  = &builder;
    storage_  = &storage;
    operands_ = &operands;
    encoder_  = encoder;

    const MicroControlFlowGraph& controlFlowGraph = builder.controlFlowGraph();
    const auto                   instructionRefs  = controlFlowGraph.instructionRefs();
    instructionRefs_.assign(instructionRefs.begin(), instructionRefs.end());
    instrInfos_.resize(storage.slotCount());

    for (auto instRef : instructionRefs_)
    {
        const uint32_t slot = instRef.get();

        InstrInfo& info = instrInfos_[slot];
        info.instRef    = instRef;

        const MicroInstr* inst = storage.ptr(instRef);
        SWC_ASSERT(inst != nullptr);
        if (inst)
            info.useDef = inst->collectUseDef(operands, encoder);
    }

    buildBlocks(controlFlowGraph);
    computeDominators();
    placePhiNodes();
    renameIntoSsa();

    valid_ = true;
}

void MicroSsaState::clear()
{
    builder_  = nullptr;
    storage_  = nullptr;
    operands_ = nullptr;
    encoder_  = nullptr;
    instrInfos_.clear();
    instructionRefs_.clear();
    instructionToBlock_.clear();
    blocks_.clear();
    valueInfos_.clear();
    phiInfos_.clear();
    valid_ = false;
}

void MicroSsaState::invalidate()
{
    valid_ = false;
}

MicroSsaState::ReachingDef MicroSsaState::reachingDef(const MicroReg reg, const MicroInstrRef beforeInstRef) const
{
    SWC_ASSERT(storage_ != nullptr);

    if (!valid_ || !isTrackedReg(reg))
        return {};

    const uint32_t slot = beforeInstRef.get();
    if (slot >= instrInfos_.size())
        return {};

    const uint32_t valueId = findRegValue(instrInfos_[slot].reachingValues, reg);
    if (valueId == K_INVALID_VALUE)
        return {};

    const ValueInfo* valueInfo = this->valueInfo(valueId);
    if (!valueInfo)
        return {};

    ReachingDef result;
    result.valueId = valueId;
    result.instRef = valueInfo->instRef;
    result.isPhi   = valueInfo->isPhi();
    if (!result.isPhi)
        result.inst = storage_->ptr(result.instRef);
    return result;
}

bool MicroSsaState::isRegUsedAfter(const MicroReg reg, const MicroInstrRef afterInstRef) const
{
    uint32_t valueId = K_INVALID_VALUE;
    if (!defValue(reg, afterInstRef, valueId))
        return false;

    return isValueTransitivelyUsed(valueId);
}

const MicroInstrUseDef* MicroSsaState::instrUseDef(const MicroInstrRef instRef) const
{
    if (!valid_)
        return nullptr;

    const uint32_t slot = instRef.get();
    if (slot >= instrInfos_.size())
        return nullptr;

    return &instrInfos_[slot].useDef;
}

bool MicroSsaState::defValue(const MicroReg reg, const MicroInstrRef instRef, uint32_t& outValueId) const
{
    outValueId = K_INVALID_VALUE;
    if (!valid_ || !isTrackedReg(reg))
        return false;

    const uint32_t slot = instRef.get();
    if (slot >= instrInfos_.size())
        return false;

    outValueId = findRegValue(instrInfos_[slot].defValues, reg);
    return outValueId != K_INVALID_VALUE;
}

const MicroSsaState::ValueInfo* MicroSsaState::valueInfo(const uint32_t valueId) const
{
    if (valueId >= valueInfos_.size())
        return nullptr;
    return &valueInfos_[valueId];
}

const MicroSsaState::PhiInfo* MicroSsaState::phiInfo(const uint32_t phiIndex) const
{
    if (phiIndex >= phiInfos_.size())
        return nullptr;
    return &phiInfos_[phiIndex];
}

const MicroSsaState::PhiInfo* MicroSsaState::phiInfoForValue(const uint32_t valueId) const
{
    const ValueInfo* info = valueInfo(valueId);
    if (!info || !info->isPhi())
        return nullptr;

    return phiInfo(info->phiIndex);
}

void MicroSsaState::buildBlocks(const MicroControlFlowGraph& controlFlowGraph)
{
    blocks_.clear();
    instructionToBlock_.assign(instructionRefs_.size(), K_INVALID_BLOCK);

    if (instructionRefs_.empty())
        return;

    std::vector<uint8_t> leaders(instructionRefs_.size(), 0);
    leaders[0] = 1;

    for (uint32_t instructionIndex = 0; instructionIndex < instructionRefs_.size(); ++instructionIndex)
    {
        const auto& successors = controlFlowGraph.successors(instructionIndex);
        if (instructionIndex + 1 < instructionRefs_.size())
        {
            const bool isLinearFallthrough = successors.size() == 1 && successors.front() == instructionIndex + 1;
            if (!isLinearFallthrough)
                leaders[instructionIndex + 1] = 1;
        }

        for (const uint32_t successorIndex : successors)
        {
            if (successorIndex != instructionIndex + 1 && successorIndex < leaders.size())
                leaders[successorIndex] = 1;
        }
    }

    uint32_t instructionIndex = 0;
    while (instructionIndex < instructionRefs_.size())
    {
        BlockInfo block;
        block.instructionBegin = instructionIndex;

        uint32_t instructionEnd = instructionIndex + 1;
        while (instructionEnd < instructionRefs_.size() && !leaders[instructionEnd])
            ++instructionEnd;
        block.instructionEnd = instructionEnd;

        const uint32_t blockIndex = static_cast<uint32_t>(blocks_.size());
        blocks_.push_back(std::move(block));
        for (uint32_t idx = instructionIndex; idx < instructionEnd; ++idx)
            instructionToBlock_[idx] = blockIndex;

        instructionIndex = instructionEnd;
    }

    for (auto& block : blocks_)
    {
        SWC_ASSERT(block.instructionEnd > block.instructionBegin);
        const uint32_t lastInstruction = block.instructionEnd - 1;
        const auto&    successors      = controlFlowGraph.successors(lastInstruction);
        for (const uint32_t successorIndex : successors)
        {
            if (successorIndex >= instructionToBlock_.size())
                continue;

            const uint32_t successorBlock = instructionToBlock_[successorIndex];
            if (successorBlock == K_INVALID_BLOCK)
                continue;

            appendUniqueIndex(block.successors, successorBlock);
        }
    }

    for (uint32_t blockIndex = 0; blockIndex < blocks_.size(); ++blockIndex)
    {
        for (const uint32_t successorBlock : blocks_[blockIndex].successors)
            appendUniqueIndex(blocks_[successorBlock].predecessors, blockIndex);
    }
}

void MicroSsaState::computeDominators()
{
    std::vector<uint32_t> idomValues(blocks_.size(), K_INVALID_BLOCK);
    for (BlockInfo& block : blocks_)
    {
        block.idom = K_INVALID_BLOCK;
        block.domChildren.clear();
        block.dominanceFrontier.clear();
    }

    if (blocks_.empty())
        return;

    std::vector<uint8_t>     visited(blocks_.size(), 0);
    SmallVector<uint32_t, 8> roots;
    roots.push_back(0);
    for (uint32_t blockIndex = 0; blockIndex < blocks_.size(); ++blockIndex)
    {
        if (blocks_[blockIndex].predecessors.empty())
            appendUniqueIndex(roots, blockIndex);
    }

    size_t rootCursor = 0;
    while (true)
    {
        uint32_t rootBlock = K_INVALID_BLOCK;
        if (rootCursor < roots.size())
            rootBlock = roots[rootCursor++];
        else
        {
            for (uint32_t blockIndex = 0; blockIndex < blocks_.size(); ++blockIndex)
            {
                if (!visited[blockIndex])
                {
                    rootBlock = blockIndex;
                    break;
                }
            }
        }

        if (rootBlock == K_INVALID_BLOCK)
            break;
        if (rootBlock >= blocks_.size() || visited[rootBlock])
            continue;

        std::vector<uint32_t> dfsStack;
        std::vector<uint32_t> dfsIter;
        std::vector<uint32_t> postOrder;
        dfsStack.push_back(rootBlock);
        dfsIter.push_back(0);
        visited[rootBlock] = 1;

        while (!dfsStack.empty())
        {
            const uint32_t blockIndex = dfsStack.back();
            uint32_t&      iterIndex  = dfsIter.back();
            const auto&    successors = blocks_[blockIndex].successors;

            if (iterIndex < successors.size())
            {
                const uint32_t successorBlock = successors[iterIndex++];
                if (successorBlock < blocks_.size() && !visited[successorBlock])
                {
                    visited[successorBlock] = 1;
                    dfsStack.push_back(successorBlock);
                    dfsIter.push_back(0);
                }

                continue;
            }

            postOrder.push_back(blockIndex);
            dfsStack.pop_back();
            dfsIter.pop_back();
        }

        std::vector<uint32_t> rpo(postOrder.rbegin(), postOrder.rend());
        std::vector<uint32_t> rpoPosition(blocks_.size(), K_INVALID_INDEX);
        for (uint32_t rpoIndex = 0; rpoIndex < rpo.size(); ++rpoIndex)
            rpoPosition[rpo[rpoIndex]] = rpoIndex;

        idomValues[rootBlock] = rootBlock;
        bool changed          = true;
        while (changed)
        {
            changed = false;
            for (uint32_t rpoIndex = 1; rpoIndex < rpo.size(); ++rpoIndex)
            {
                const uint32_t blockIndex = rpo[rpoIndex];
                uint32_t       newIdom    = K_INVALID_BLOCK;

                for (const uint32_t predecessorBlock : blocks_[blockIndex].predecessors)
                {
                    if (predecessorBlock >= blocks_.size())
                        continue;
                    if (rpoPosition[predecessorBlock] == K_INVALID_INDEX)
                        continue;
                    if (idomValues[predecessorBlock] == K_INVALID_BLOCK)
                        continue;

                    if (newIdom == K_INVALID_BLOCK)
                    {
                        newIdom = predecessorBlock;
                        continue;
                    }

                    const uint32_t intersectedIdom = intersectIdom(predecessorBlock, newIdom, idomValues, rpoPosition);
                    if (intersectedIdom == K_INVALID_BLOCK_INDEX)
                        continue;
                    newIdom = intersectedIdom;
                }

                if (newIdom == K_INVALID_BLOCK)
                    continue;

                if (idomValues[blockIndex] != newIdom)
                {
                    idomValues[blockIndex] = newIdom;
                    changed                = true;
                }
            }
        }
    }

    for (uint32_t blockIndex = 0; blockIndex < blocks_.size(); ++blockIndex)
    {
        blocks_[blockIndex].idom = idomValues[blockIndex];
        const uint32_t idom      = blocks_[blockIndex].idom;
        if (idom == K_INVALID_BLOCK || idom == blockIndex)
            continue;
        appendUniqueIndex(blocks_[idom].domChildren, blockIndex);
    }

    for (uint32_t blockIndex = 0; blockIndex < blocks_.size(); ++blockIndex)
    {
        if (blocks_[blockIndex].predecessors.size() < 2)
            continue;

        for (const uint32_t predecessorBlock : blocks_[blockIndex].predecessors)
        {
            uint32_t runner = predecessorBlock;
            while (runner != K_INVALID_BLOCK && runner != blocks_[blockIndex].idom)
            {
                appendUniqueIndex(blocks_[runner].dominanceFrontier, blockIndex);
                const uint32_t runnerIdom = blocks_[runner].idom;
                if (runnerIdom == runner)
                    break;
                runner = runnerIdom;
            }
        }
    }
}

void MicroSsaState::placePhiNodes()
{
    std::unordered_map<MicroReg, std::vector<uint32_t>> defBlocksByReg;
    defBlocksByReg.reserve(64);

    for (uint32_t blockIndex = 0; blockIndex < blocks_.size(); ++blockIndex)
    {
        const BlockInfo& block = blocks_[blockIndex];
        for (uint32_t instructionIndex = block.instructionBegin; instructionIndex < block.instructionEnd; ++instructionIndex)
        {
            const MicroInstrRef instRef = instructionRefs_[instructionIndex];
            const InstrInfo&    info    = instrInfos_[instRef.get()];
            for (const MicroReg reg : info.useDef.defs)
            {
                if (!isTrackedReg(reg))
                    continue;

                auto& regDefBlocks = defBlocksByReg[reg];
                if (regDefBlocks.empty() || regDefBlocks.back() != blockIndex)
                    regDefBlocks.push_back(blockIndex);
            }
        }
    }

    for (auto& [reg, defBlocks] : defBlocksByReg)
    {
        std::vector<uint8_t>  inWork(blocks_.size(), 0);
        std::vector<uint8_t>  hasPhi(blocks_.size(), 0);
        std::vector<uint32_t> workList;
        workList.reserve(defBlocks.size());

        for (const uint32_t blockIndex : defBlocks)
        {
            if (blockIndex >= blocks_.size())
                continue;

            workList.push_back(blockIndex);
            inWork[blockIndex] = 1;
        }

        while (!workList.empty())
        {
            const uint32_t blockIndex = workList.back();
            workList.pop_back();

            for (const uint32_t frontierBlock : blocks_[blockIndex].dominanceFrontier)
            {
                if (frontierBlock >= blocks_.size() || hasPhi[frontierBlock])
                    continue;

                ensurePhi(frontierBlock, reg);
                hasPhi[frontierBlock] = 1;

                if (!inWork[frontierBlock])
                {
                    inWork[frontierBlock] = 1;
                    workList.push_back(frontierBlock);
                }
            }
        }
    }
}

void MicroSsaState::renameIntoSsa()
{
    valueInfos_.clear();

    RenameState state;
    state.currentValues.reserve(64);

    for (uint32_t blockIndex = 0; blockIndex < blocks_.size(); ++blockIndex)
    {
        if (blocks_[blockIndex].idom == blockIndex)
            renameBlock(blockIndex, state);
    }
}

void MicroSsaState::renameBlock(const uint32_t blockIndex, RenameState& state)
{
    BlockInfo&                block = blocks_[blockIndex];
    std::vector<RestorePoint> restores;
    restores.reserve(block.phis.size() + (block.instructionEnd - block.instructionBegin));

    for (const uint32_t phiIndex : block.phis)
    {
        PhiInfo& phi      = phiInfos_[phiIndex];
        phi.resultValueId = createValue(phi.reg, blockIndex, MicroInstrRef::invalid(), phiIndex);
        pushCurrentValue(restores, state, phi.reg, phi.resultValueId);
    }

    for (uint32_t instructionIndex = block.instructionBegin; instructionIndex < block.instructionEnd; ++instructionIndex)
    {
        const MicroInstrRef instRef = instructionRefs_[instructionIndex];
        InstrInfo&          info    = instrInfos_[instRef.get()];

        captureReachingUses(info.reachingValues, info.useDef, state.currentValues);

        for (const MicroReg reg : info.useDef.uses)
        {
            if (!isTrackedReg(reg))
                continue;

            const auto currentValue = state.currentValues.find(reg);
            if (currentValue == state.currentValues.end())
                continue;

            appendValueUse(currentValue->second, UseSite{
                                                     .kind     = UseSite::Kind::Instruction,
                                                     .instRef  = instRef,
                                                     .phiIndex = K_INVALID_PHI,
                                                 });
        }

        info.defValues.clear();
        for (const MicroReg reg : info.useDef.defs)
        {
            if (!isTrackedReg(reg))
                continue;

            const uint32_t valueId = createValue(reg, blockIndex, instRef, K_INVALID_PHI);
            info.defValues.push_back(RegValueEntry{reg, valueId});
            pushCurrentValue(restores, state, reg, valueId);
        }
    }

    for (const uint32_t successorBlock : block.successors)
        assignPhiInputs(blockIndex, successorBlock, state.currentValues);

    for (const uint32_t childBlock : block.domChildren)
        renameBlock(childBlock, state);

    for (auto& restore : std::views::reverse(restores))
    {
        if (!restore.hadPrevious)
            state.currentValues.erase(restore.reg);
        else
            state.currentValues[restore.reg] = restore.previousId;
    }
}

void MicroSsaState::captureReachingUses(SmallVector4<RegValueEntry>& out, const MicroInstrUseDef& useDef, const std::unordered_map<MicroReg, uint32_t>& currentValues)
{
    out.clear();
    out.reserve(useDef.uses.size());

    for (const MicroReg reg : useDef.uses)
    {
        if (!isTrackedReg(reg))
            continue;

        const auto currentValue = currentValues.find(reg);
        if (currentValue == currentValues.end())
            continue;

        out.push_back(RegValueEntry{reg, currentValue->second});
    }
}

void MicroSsaState::assignPhiInputs(const uint32_t predecessorBlock, const uint32_t successorBlock, const std::unordered_map<MicroReg, uint32_t>& currentValues)
{
    if (successorBlock >= blocks_.size())
        return;

    BlockInfo& successor = blocks_[successorBlock];
    for (const uint32_t phiIndex : successor.phis)
    {
        PhiInfo& phi      = phiInfos_[phiIndex];
        uint32_t predSlot = K_INVALID_INDEX;
        for (uint32_t idx = 0; idx < phi.predecessorBlocks.size(); ++idx)
        {
            if (phi.predecessorBlocks[idx] == predecessorBlock)
            {
                predSlot = idx;
                break;
            }
        }

        if (predSlot == K_INVALID_INDEX)
            continue;

        const auto currentValue = currentValues.find(phi.reg);
        if (currentValue == currentValues.end())
            continue;

        phi.incomingValueIds[predSlot] = currentValue->second;
        appendValueUse(currentValue->second, UseSite{
                                                 .kind     = UseSite::Kind::Phi,
                                                 .instRef  = MicroInstrRef::invalid(),
                                                 .phiIndex = phiIndex,
                                             });
    }
}

void MicroSsaState::pushCurrentValue(std::vector<RestorePoint>& restores, RenameState& state, const MicroReg reg, const uint32_t valueId)
{
    RestorePoint restore;
    restore.reg = reg;

    const auto previous = state.currentValues.find(reg);
    if (previous != state.currentValues.end())
    {
        restore.hadPrevious = true;
        restore.previousId  = previous->second;
    }

    restores.push_back(restore);
    state.currentValues[reg] = valueId;
}

uint32_t MicroSsaState::createValue(const MicroReg reg, const uint32_t blockIndex, const MicroInstrRef instRef, const uint32_t phiIndex)
{
    const uint32_t valueId = static_cast<uint32_t>(valueInfos_.size());
    valueInfos_.push_back(ValueInfo{
        .reg        = reg,
        .instRef    = instRef,
        .blockIndex = blockIndex,
        .phiIndex   = phiIndex,
    });

    return valueId;
}

uint32_t MicroSsaState::ensurePhi(const uint32_t blockIndex, const MicroReg reg)
{
    BlockInfo& block = blocks_[blockIndex];
    for (const uint32_t phiIndex : block.phis)
    {
        if (phiInfos_[phiIndex].reg == reg)
            return phiIndex;
    }

    const uint32_t phiIndex = static_cast<uint32_t>(phiInfos_.size());
    PhiInfo        phi;
    phi.reg        = reg;
    phi.blockIndex = blockIndex;
    phi.predecessorBlocks.assign(block.predecessors.begin(), block.predecessors.end());
    phi.incomingValueIds.resize(phi.predecessorBlocks.size(), K_INVALID_VALUE);
    phiInfos_.push_back(std::move(phi));
    block.phis.push_back(phiIndex);
    return phiIndex;
}

void MicroSsaState::appendValueUse(const uint32_t valueId, const UseSite& useSite)
{
    if (valueId >= valueInfos_.size())
        return;

    valueInfos_[valueId].uses.push_back(useSite);
}

bool MicroSsaState::isValueTransitivelyUsed(const uint32_t valueId) const
{
    if (valueId >= valueInfos_.size())
        return false;

    std::vector<uint8_t>  visited(valueInfos_.size(), 0);
    std::vector<uint32_t> stack;
    stack.push_back(valueId);

    while (!stack.empty())
    {
        const uint32_t currentValueId = stack.back();
        stack.pop_back();

        if (currentValueId >= valueInfos_.size())
            continue;
        if (visited[currentValueId])
            continue;
        visited[currentValueId] = 1;

        const ValueInfo& info = valueInfos_[currentValueId];
        for (const UseSite& useSite : info.uses)
        {
            if (useSite.kind == UseSite::Kind::Instruction)
                return true;

            if (useSite.kind != UseSite::Kind::Phi)
                continue;

            const PhiInfo* phi = phiInfo(useSite.phiIndex);
            if (!phi)
                continue;
            if (phi->resultValueId == K_INVALID_VALUE)
                continue;

            stack.push_back(phi->resultValueId);
        }
    }

    return false;
}

SWC_END_NAMESPACE();
