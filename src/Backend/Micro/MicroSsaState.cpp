#include "pch.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroPassContext.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_INVALID = std::numeric_limits<uint32_t>::max();

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

    // Cooper-Harvey-Kennedy finger-walk over the dom tree.
    uint32_t intersectIdom(uint32_t                     lhs,
                           uint32_t                     rhs,
                           const std::vector<uint32_t>& idom,
                           const std::vector<uint32_t>& rpoPosition)
    {
        while (lhs != rhs)
        {
            while (rpoPosition[lhs] > rpoPosition[rhs])
                lhs = idom[lhs];
            while (rpoPosition[rhs] > rpoPosition[lhs])
                rhs = idom[rhs];
        }

        return lhs;
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
    instructionIndexBySlot_.assign(storage.slotCount(), K_INVALID);

    for (uint32_t instructionIndex = 0; instructionIndex < instructionRefs_.size(); ++instructionIndex)
    {
        const MicroInstrRef instRef = instructionRefs_[instructionIndex];
        const uint32_t      slot    = instRef.get();

        instructionIndexBySlot_[slot] = instructionIndex;
        InstrInfo& info               = instrInfos_[slot];
        info.instRef                  = instRef;

        const MicroInstr* inst = storage.ptr(instRef);
        SWC_ASSERT(inst != nullptr);
        info.useDef = inst->collectUseDef(operands, encoder);

        for (const MicroReg reg : info.useDef.defs)
        {
            if (!isTrackedReg(reg))
                continue;

            const uint32_t regIndex = trackedRegs_.ensure(reg);
            info.defRegIndices.push_back(regIndex);
            ++trackedDefCount_;
        }
    }

    for (const MicroInstrRef instRef : instructionRefs_)
    {
        InstrInfo& info = instrInfos_[instRef.get()];
        for (const MicroReg reg : info.useDef.uses)
        {
            if (!isTrackedReg(reg))
                continue;

            const uint32_t regIndex = trackedRegs_.find(reg);
            if (regIndex != MicroDenseRegIndex::K_INVALID_INDEX)
                info.useRegIndices.push_back(regIndex);
        }
    }

    buildBlocks(controlFlowGraph);
    computeDominators();
    placePhiNodes();
    renameIntoSsa();

    valid_ = true;
}

const MicroSsaState* MicroSsaState::ensureFor(const MicroPassContext& context, MicroSsaState& localState)
{
    if (context.ssaState)
        return context.ssaState;
    if (!context.builder || !context.instructions || !context.operands)
        return nullptr;

    localState.build(*context.builder, *context.instructions, *context.operands, context.encoder);
    return &localState;
}

void MicroSsaState::clear()
{
    builder_  = nullptr;
    storage_  = nullptr;
    operands_ = nullptr;
    encoder_  = nullptr;
    trackedRegs_.clear();
    instrInfos_.clear();
    instructionRefs_.clear();
    instructionIndexBySlot_.clear();
    instructionToBlock_.clear();
    blocks_.clear();
    valueInfos_.clear();
    phiInfos_.clear();
    trackedDefCount_ = 0;
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
    SWC_ASSERT(slot < instrInfos_.size());
    SWC_ASSERT(slot < instructionIndexBySlot_.size());

    const uint32_t instructionIndex = instructionIndexBySlot_[slot];
    if (instructionIndex == K_INVALID || instructionIndex >= instructionToBlock_.size())
        return {};

    const uint32_t blockIndex = instructionToBlock_[instructionIndex];
    if (blockIndex == K_INVALID_BLOCK || blockIndex >= blocks_.size())
        return {};

    const BlockInfo& block   = blocks_[blockIndex];
    uint32_t         valueId = K_INVALID_VALUE;
    for (uint32_t scanIndex = instructionIndex; scanIndex > block.instructionBegin; --scanIndex)
    {
        const MicroInstrRef scanRef = instructionRefs_[scanIndex - 1];
        const InstrInfo&    info    = instrInfos_[scanRef.get()];
        valueId                     = findRegValue(info.defValues, reg);
        if (valueId != K_INVALID_VALUE)
            break;
    }

    if (valueId == K_INVALID_VALUE)
        valueId = findRegValue(block.entryValues, reg);
    if (valueId == K_INVALID_VALUE)
        return {};

    const ValueInfo& info = valueInfos_[valueId];
    ReachingDef      result;
    result.valueId = valueId;
    result.instRef = info.instRef;
    result.isPhi   = info.isPhi();
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
    SWC_ASSERT(slot < instrInfos_.size());
    return &instrInfos_[slot].useDef;
}

bool MicroSsaState::defValue(const MicroReg reg, const MicroInstrRef instRef, uint32_t& outValueId) const
{
    outValueId = K_INVALID_VALUE;
    if (!valid_ || !isTrackedReg(reg))
        return false;

    const uint32_t slot = instRef.get();
    SWC_ASSERT(slot < instrInfos_.size());
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
            if (successorIndex == instructionIndex + 1)
                continue;
            SWC_ASSERT(successorIndex < leaders.size());
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
            SWC_ASSERT(successorIndex < instructionToBlock_.size());
            const uint32_t successorBlock = instructionToBlock_[successorIndex];
            SWC_ASSERT(successorBlock != K_INVALID_BLOCK);
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
    std::vector idomValues(blocks_.size(), K_INVALID_BLOCK);
    for (BlockInfo& block : blocks_)
    {
        block.idom = K_INVALID_BLOCK;
        block.domChildren.clear();
        block.dominanceFrontier.clear();
    }

    if (blocks_.empty())
        return;

    // Seed roots: entry block plus any predecessor-less block (covers unreachable
    // sub-graphs). Fall back to scanning unvisited blocks for cycles unreachable
    // from any seed.
    std::vector<uint8_t>     visited(blocks_.size(), 0);
    SmallVector<uint32_t, 8> roots;
    roots.push_back(0);
    for (uint32_t blockIndex = 1; blockIndex < blocks_.size(); ++blockIndex)
    {
        if (blocks_[blockIndex].predecessors.empty())
            roots.push_back(blockIndex);
    }

    std::vector<uint32_t> dfsStack;
    std::vector<uint32_t> dfsIter;
    std::vector<uint32_t> postOrder;
    std::vector           rpoPosition(blocks_.size(), K_INVALID);
    std::vector<uint32_t> rpoStamp(blocks_.size(), 0);
    uint32_t              currentRpoStamp = 1;
    dfsStack.reserve(blocks_.size());
    dfsIter.reserve(blocks_.size());
    postOrder.reserve(blocks_.size());

    size_t rootCursor = 0;
    while (true)
    {
        uint32_t rootBlock = K_INVALID;
        while (rootCursor < roots.size())
        {
            const uint32_t candidate = roots[rootCursor++];
            if (!visited[candidate])
            {
                rootBlock = candidate;
                break;
            }
        }
        if (rootBlock == K_INVALID)
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
        if (rootBlock == K_INVALID)
            break;

        dfsStack.clear();
        dfsIter.clear();
        postOrder.clear();
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
                if (!visited[successorBlock])
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

        if (currentRpoStamp == std::numeric_limits<uint32_t>::max())
        {
            std::ranges::fill(rpoStamp, 0);
            currentRpoStamp = 1;
        }

        const uint32_t rpoComponentStamp = currentRpoStamp++;
        const uint32_t rpoSize = static_cast<uint32_t>(postOrder.size());
        for (uint32_t i = 0; i < rpoSize; ++i)
        {
            const uint32_t blockIndex = postOrder[rpoSize - 1 - i];
            rpoPosition[blockIndex]   = i;
            rpoStamp[blockIndex]      = rpoComponentStamp;
        }

        idomValues[rootBlock] = rootBlock;
        bool changed          = true;
        while (changed)
        {
            changed = false;
            for (uint32_t i = 1; i < rpoSize; ++i)
            {
                const uint32_t blockIndex = postOrder[rpoSize - 1 - i];
                uint32_t       newIdom    = K_INVALID;

                for (const uint32_t predecessorBlock : blocks_[blockIndex].predecessors)
                {
                    if (rpoStamp[predecessorBlock] != rpoComponentStamp)
                        continue;
                    if (idomValues[predecessorBlock] == K_INVALID_BLOCK)
                        continue;

                    if (newIdom == K_INVALID)
                        newIdom = predecessorBlock;
                    else
                        newIdom = intersectIdom(predecessorBlock, newIdom, idomValues, rpoPosition);
                }

                if (newIdom != K_INVALID && idomValues[blockIndex] != newIdom)
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
    std::vector<SmallVector4<uint32_t>> defBlocksByReg(trackedRegs_.regs().size());

    for (uint32_t blockIndex = 0; blockIndex < blocks_.size(); ++blockIndex)
    {
        const BlockInfo& block = blocks_[blockIndex];
        for (uint32_t instructionIndex = block.instructionBegin; instructionIndex < block.instructionEnd; ++instructionIndex)
        {
            const MicroInstrRef instRef = instructionRefs_[instructionIndex];
            const InstrInfo&    info    = instrInfos_[instRef.get()];
            for (const uint32_t regIndex : info.defRegIndices)
            {
                auto& regDefBlocks = defBlocksByReg[regIndex];
                if (regDefBlocks.empty() || regDefBlocks.back() != blockIndex)
                    regDefBlocks.push_back(blockIndex);
            }
        }
    }

    std::vector<uint32_t> inWorkStamp(blocks_.size(), 0);
    std::vector<uint32_t> hasPhiStamp(blocks_.size(), 0);
    std::vector<uint32_t> workList;
    uint32_t              stamp = 1;
    const auto&           regs  = trackedRegs_.regs();
    for (uint32_t regIndex = 0; regIndex < defBlocksByReg.size(); ++regIndex)
    {
        const auto& defBlocks = defBlocksByReg[regIndex];
        if (defBlocks.empty())
            continue;

        if (stamp == std::numeric_limits<uint32_t>::max())
        {
            std::ranges::fill(inWorkStamp, 0);
            std::ranges::fill(hasPhiStamp, 0);
            stamp = 1;
        }

        const uint32_t currentStamp = stamp++;
        workList.clear();
        workList.reserve(defBlocks.size());
        for (const uint32_t blockIndex : defBlocks)
        {
            SWC_ASSERT(blockIndex < blocks_.size());
            workList.push_back(blockIndex);
            inWorkStamp[blockIndex] = currentStamp;
        }

        const MicroReg reg = regs[regIndex];
        while (!workList.empty())
        {
            const uint32_t blockIndex = workList.back();
            workList.pop_back();

            for (const uint32_t frontierBlock : blocks_[blockIndex].dominanceFrontier)
            {
                if (hasPhiStamp[frontierBlock] == currentStamp)
                    continue;

                createPhi(frontierBlock, reg, regIndex);
                hasPhiStamp[frontierBlock] = currentStamp;

                if (inWorkStamp[frontierBlock] != currentStamp)
                {
                    inWorkStamp[frontierBlock] = currentStamp;
                    workList.push_back(frontierBlock);
                }
            }
        }
    }
}

void MicroSsaState::renameIntoSsa()
{
    valueInfos_.clear();
    valueInfos_.reserve(static_cast<size_t>(trackedDefCount_) + phiInfos_.size());

    RenameState  state;
    const size_t trackedRegCount = trackedRegs_.regs().size();
    state.currentValues.assign(trackedRegCount, K_INVALID_VALUE);
    state.activePositions.assign(trackedRegCount, K_INVALID);
    state.activeRegIndices.reserve(trackedRegCount);

    for (uint32_t blockIndex = 0; blockIndex < blocks_.size(); ++blockIndex)
    {
        if (blocks_[blockIndex].idom == blockIndex)
            renameBlock(blockIndex, state);
    }
}

void MicroSsaState::renameBlock(const uint32_t blockIndex, RenameState& state)
{
    BlockInfo&                 block = blocks_[blockIndex];
    SmallVector8<RestorePoint> restores;
    restores.reserve(block.phis.size() + (block.instructionEnd - block.instructionBegin));

    for (const uint32_t phiIndex : block.phis)
    {
        PhiInfo& phi      = phiInfos_[phiIndex];
        phi.resultValueId = createValue(phi.reg, blockIndex, MicroInstrRef::invalid(), phiIndex);
        pushCurrentValue(restores, state, phi.regIndex, phi.resultValueId);
    }

    captureCurrentValues(block.entryValues, state);

    const auto& regs = trackedRegs_.regs();
    for (uint32_t instructionIndex = block.instructionBegin; instructionIndex < block.instructionEnd; ++instructionIndex)
    {
        const MicroInstrRef instRef = instructionRefs_[instructionIndex];
        InstrInfo&          info    = instrInfos_[instRef.get()];

        for (const uint32_t regIndex : info.useRegIndices)
        {
            const uint32_t valueId = currentValue(state, regIndex);
            if (valueId == K_INVALID_VALUE)
                continue;

            appendValueUse(valueId, UseSite{
                                        .kind     = UseSite::Kind::Instruction,
                                        .instRef  = instRef,
                                        .phiIndex = K_INVALID_PHI,
                                    });
        }

        info.defValues.clear();
        for (const uint32_t regIndex : info.defRegIndices)
        {
            SWC_ASSERT(regIndex < regs.size());
            const MicroReg reg     = regs[regIndex];
            const uint32_t valueId = createValue(reg, blockIndex, instRef, K_INVALID_PHI);
            info.defValues.push_back(RegValueEntry{reg, valueId});
            pushCurrentValue(restores, state, regIndex, valueId);
        }
    }

    for (const uint32_t successorBlock : block.successors)
        assignPhiInputs(blockIndex, successorBlock, state);

    for (const uint32_t childBlock : block.domChildren)
        renameBlock(childBlock, state);

    for (auto& restore : std::views::reverse(restores))
    {
        if (!restore.hadPrevious)
        {
            SWC_ASSERT(restore.regIndex < state.currentValues.size());
            state.currentValues[restore.regIndex] = K_INVALID_VALUE;
            const uint32_t activePosition         = state.activePositions[restore.regIndex];
            SWC_ASSERT(activePosition < state.activeRegIndices.size());
            const uint32_t lastRegIndex            = state.activeRegIndices.back();
            state.activeRegIndices[activePosition] = lastRegIndex;
            state.activePositions[lastRegIndex]    = activePosition;
            state.activeRegIndices.pop_back();
            state.activePositions[restore.regIndex] = K_INVALID;
        }
        else
        {
            SWC_ASSERT(restore.regIndex < state.currentValues.size());
            state.currentValues[restore.regIndex] = restore.previousId;
        }
    }
}

void MicroSsaState::captureCurrentValues(SmallVector8<RegValueEntry>& out, const RenameState& state) const
{
    out.clear();
    out.reserve(state.activeRegIndices.size());

    const auto& regs = trackedRegs_.regs();
    for (const uint32_t regIndex : state.activeRegIndices)
    {
        SWC_ASSERT(regIndex < regs.size());
        SWC_ASSERT(regIndex < state.currentValues.size());
        const uint32_t valueId = state.currentValues[regIndex];
        if (valueId != K_INVALID_VALUE)
            out.push_back(RegValueEntry{regs[regIndex], valueId});
    }
}

uint32_t MicroSsaState::currentValue(const RenameState& state, const uint32_t regIndex)
{
    if (regIndex >= state.currentValues.size())
        return K_INVALID_VALUE;

    return state.currentValues[regIndex];
}

void MicroSsaState::assignPhiInputs(const uint32_t predecessorBlock, const uint32_t successorBlock, const RenameState& state)
{
    SWC_ASSERT(successorBlock < blocks_.size());
    BlockInfo& successor = blocks_[successorBlock];
    uint32_t   predSlot  = K_INVALID;
    for (uint32_t idx = 0; idx < successor.predecessors.size(); ++idx)
    {
        if (successor.predecessors[idx] == predecessorBlock)
        {
            predSlot = idx;
            break;
        }
    }

    if (predSlot == K_INVALID)
        return;

    for (const uint32_t phiIndex : successor.phis)
    {
        PhiInfo& phi = phiInfos_[phiIndex];
        SWC_ASSERT(predSlot < phi.incomingValueIds.size());
        const uint32_t valueId = currentValue(state, phi.regIndex);
        if (valueId == K_INVALID_VALUE)
            continue;

        phi.incomingValueIds[predSlot] = valueId;
        appendValueUse(valueId, UseSite{
                                    .kind     = UseSite::Kind::Phi,
                                    .instRef  = MicroInstrRef::invalid(),
                                    .phiIndex = phiIndex,
                                });
    }
}

void MicroSsaState::pushCurrentValue(SmallVector8<RestorePoint>& restores, RenameState& state, const uint32_t regIndex, const uint32_t valueId)
{
    SWC_ASSERT(regIndex < state.currentValues.size());
    SWC_ASSERT(regIndex < state.activePositions.size());

    RestorePoint restore;
    restore.regIndex = regIndex;

    const uint32_t previous = state.currentValues[regIndex];
    if (previous != K_INVALID_VALUE)
    {
        restore.hadPrevious = true;
        restore.previousId  = previous;
    }
    else
    {
        SWC_ASSERT(state.activePositions[regIndex] == K_INVALID);
        state.activePositions[regIndex] = static_cast<uint32_t>(state.activeRegIndices.size());
        state.activeRegIndices.push_back(regIndex);
    }

    restores.push_back(restore);
    state.currentValues[regIndex] = valueId;
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

uint32_t MicroSsaState::createPhi(const uint32_t blockIndex, const MicroReg reg, const uint32_t regIndex)
{
    BlockInfo& block = blocks_[blockIndex];
    const uint32_t phiIndex = static_cast<uint32_t>(phiInfos_.size());
    PhiInfo        phi;
    phi.reg        = reg;
    phi.regIndex   = regIndex;
    phi.blockIndex = blockIndex;
    phi.predecessorBlocks.assign(block.predecessors.begin(), block.predecessors.end());
    phi.incomingValueIds.resize(phi.predecessorBlocks.size(), K_INVALID_VALUE);
    phiInfos_.push_back(std::move(phi));
    block.phis.push_back(phiIndex);
    return phiIndex;
}

void MicroSsaState::appendValueUse(const uint32_t valueId, const UseSite& useSite)
{
    SWC_ASSERT(valueId < valueInfos_.size());
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
