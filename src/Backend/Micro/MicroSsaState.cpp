#include "pch.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Support/Report/Assert.h"

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
    uint32_t intersectIdom(uint32_t lhs, uint32_t rhs, const std::vector<uint32_t>& idom, const std::vector<uint32_t>& rpoPosition)
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
    resetForBuild(builder, storage, operands, encoder);

    const MicroControlFlowGraph& controlFlowGraph = builder.controlFlowGraph();
    const auto                   instructionRefs  = controlFlowGraph.instructionRefs();
    instructionRefs_.assign(instructionRefs.begin(), instructionRefs.end());
    instructionIndexBySlot_.assign(storage.slotCount(), K_INVALID);

    for (uint32_t instructionIndex = 0; instructionIndex < instructionRefs_.size(); ++instructionIndex)
    {
        const MicroInstrRef instRef = instructionRefs_[instructionIndex];
        const uint32_t      slot    = instRef.get();

        instructionIndexBySlot_[slot] = instructionIndex;
        InstrInfo& info               = instrInfos_[slot];

        const MicroInstr* inst = storage.ptr(instRef);
        SWC_ASSERT(inst != nullptr);

        // Reuse the cached use/def when this slot still holds an instruction with the
        // same opcode and operand words as the previous build; otherwise recompute and
        // refresh the cache. See InstrInfo for why this key is sound.
        const MicroInstrOperand* ops         = inst->ops(operands);
        const uint8_t            numOperands = inst->numOperands;
        bool                     reuseUseDef = info.useDefCached && info.cachedOp == inst->op && info.cachedNumOperands == numOperands && info.cachedOperandWords.size() == numOperands;
        if (reuseUseDef)
        {
            for (uint8_t i = 0; i < numOperands; ++i)
            {
                if (info.cachedOperandWords[i] != ops[i].valueU64)
                {
                    reuseUseDef = false;
                    break;
                }
            }
        }

        if (!reuseUseDef)
        {
            info.useDef = inst->collectUseDef(operands, encoder);

            info.cachedOp          = inst->op;
            info.cachedNumOperands = numOperands;
            info.useDefCached      = true;
            info.cachedOperandWords.clear();
            for (uint8_t i = 0; i < numOperands; ++i)
                info.cachedOperandWords.push_back(ops[i].valueU64);
        }

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

    {
        buildBlocks(controlFlowGraph);
    }
    {
        computeDominators();
    }
    {
        placePhiNodes();
    }
    {
        renameIntoSsa();
    }

    valid_ = true;
}

const MicroSsaState* MicroSsaState::ensureFor(const MicroPassContext& context, MicroSsaState& localState)
{
    if (context.ssaState)
    {
        if (!context.ssaState->isValid())
        {
            if (!context.builder || !context.instructions || !context.operands)
                return nullptr;

            context.ssaState->build(*context.builder, *context.instructions, *context.operands, context.encoder);
        }

        return context.ssaState;
    }
    if (!context.builder || !context.instructions || !context.operands)
        return nullptr;

    if (!localState.isValid())
        localState.build(*context.builder, *context.instructions, *context.operands, context.encoder);

    return &localState;
}

void MicroSsaState::resetForBuild(MicroBuilder& builder, MicroStorage& storage, MicroOperandStorage& operands, const Encoder* encoder)
{
    valid_    = false;
    builder_  = &builder;
    storage_  = &storage;
    operands_ = &operands;
    encoder_  = encoder;

    trackedRegs_.clear();
    instructionRefs_.clear();
    instructionIndexBySlot_.clear();
    instructionToBlock_.clear();
    blocks_.clear();
    trackedDefCount_ = 0;
    valueInfoCount_  = 0;
    phiInfoCount_    = 0;

    resetInstructionInfos(storage.slotCount());
}

void MicroSsaState::resetInstructionInfos(const uint32_t slotCount)
{
    if (instrInfos_.size() < slotCount)
        instrInfos_.resize(slotCount);

    for (uint32_t slot = 0; slot < slotCount; ++slot)
    {
        InstrInfo& info = instrInfos_[slot];
        // info.useDef and the cachedOp/cachedOperandWords/useDefCached fields are kept
        // on purpose: they form the cross-rebuild use/def cache (see InstrInfo). Only
        // the per-build SSA bookkeeping is cleared here.
        info.defValues.clear();
        info.useRegIndices.clear();
        info.defRegIndices.clear();
        info.renamePosition = K_INVALID_VALUE;
    }
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
    reachingValuesByReg_.clear();
    useVisitStamps_.clear();
    useVisitStack_.clear();
    trackedDefCount_ = 0;
    valueInfoCount_  = 0;
    phiInfoCount_    = 0;
    useVisitStamp_   = 1;
    valid_           = false;
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

    const uint32_t regIndex = trackedRegs_.find(reg);
    if (regIndex == MicroDenseRegIndex::K_INVALID_INDEX)
        return {};

    const uint32_t position = instrInfos_[slot].renamePosition;
    const auto&    values   = reachingValuesByReg_[regIndex];
    const auto     after    = std::ranges::upper_bound(values, position, {}, &ReachingValue::position);
    if (after == values.begin())
        return {};
    const uint32_t valueId = (after - 1)->valueId;
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
    if (slot >= instructionIndexBySlot_.size())
        return nullptr;
    if (instructionIndexBySlot_[slot] == K_INVALID)
        return nullptr;
    SWC_ASSERT(slot < instrInfos_.size());
    return &instrInfos_[slot].useDef;
}

bool MicroSsaState::defValue(const MicroReg reg, const MicroInstrRef instRef, uint32_t& outValueId) const
{
    outValueId = K_INVALID_VALUE;
    if (!valid_ || !isTrackedReg(reg))
        return false;

    const uint32_t slot = instRef.get();
    if (slot >= instructionIndexBySlot_.size())
        return false;
    if (instructionIndexBySlot_[slot] == K_INVALID)
        return false;
    SWC_ASSERT(slot < instrInfos_.size());
    outValueId = findRegValue(instrInfos_[slot].defValues, reg);
    return outValueId != K_INVALID_VALUE;
}

const MicroSsaState::ValueInfo* MicroSsaState::valueInfo(const uint32_t valueId) const
{
    if (valueId >= valueInfoCount_)
        return nullptr;
    return &valueInfos_[valueId];
}

const MicroSsaState::PhiInfo* MicroSsaState::phiInfo(const uint32_t phiIndex) const
{
    if (phiIndex >= phiInfoCount_)
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
            blocks_[successorBlock].predecessors.push_back(blockIndex);
    }
}

void MicroSsaState::computeDominators()
{
    // A single block dominates itself, with no frontier. Avoid setting up the
    // general DFS and fixed-point workspaces for straight-line functions.
    if (blocks_.size() == 1)
    {
        blocks_[0].idom = 0;
        return;
    }

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

    size_t   rootCursor      = 0;
    uint32_t unvisitedCursor = 0;
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
            // Visited blocks never become unvisited. Do not rescan the prefix
            // for every disconnected component (including unreachable cycles).
            while (unvisitedCursor < blocks_.size() && visited[unvisitedCursor])
                ++unvisitedCursor;
            if (unvisitedCursor < blocks_.size())
                rootBlock = unvisitedCursor;
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
        const uint32_t rpoSize           = static_cast<uint32_t>(postOrder.size());
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
        blocks_[idom].domChildren.push_back(blockIndex);
    }

    // Each join is visited once. Once two predecessor walks meet, the remaining
    // dominator path has already contributed this join to every frontier on it.
    std::vector<uint32_t> frontierVisit(blocks_.size(), K_INVALID_BLOCK);
    for (uint32_t blockIndex = 0; blockIndex < blocks_.size(); ++blockIndex)
    {
        if (blocks_[blockIndex].predecessors.size() < 2)
            continue;

        for (const uint32_t predecessorBlock : blocks_[blockIndex].predecessors)
        {
            uint32_t runner = predecessorBlock;
            while (runner != K_INVALID_BLOCK && runner != blocks_[blockIndex].idom)
            {
                if (frontierVisit[runner] == blockIndex)
                    break;
                frontierVisit[runner] = blockIndex;
                blocks_[runner].dominanceFrontier.push_back(blockIndex);
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
    if (blocks_.size() < 2)
        return;

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
    valueInfoCount_ = 0;
    valueInfos_.reserve(static_cast<size_t>(trackedDefCount_) + phiInfoCount_);

    RenameState  state;
    const size_t trackedRegCount = trackedRegs_.regs().size();
    state.currentValues.assign(trackedRegCount, K_INVALID_VALUE);
    reachingValuesByReg_.resize(trackedRegCount);
    for (auto& values : reachingValuesByReg_)
        values.clear();

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

    const auto& regs = trackedRegs_.regs();
    for (uint32_t instructionIndex = block.instructionBegin; instructionIndex < block.instructionEnd; ++instructionIndex)
    {
        const MicroInstrRef instRef = instructionRefs_[instructionIndex];
        InstrInfo&          info    = instrInfos_[instRef.get()];

        // Queries observe the state before this instruction's writes. Its defs,
        // and any scope restores before the next instruction, take effect at the
        // next position in the rename walk, independently of physical IR order.
        info.renamePosition = state.position++;

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

    for (const auto& restore : std::views::reverse(restores))
        setCurrentValue(state, restore.regIndex, restore.previousId);
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
    restores.push_back(RestorePoint{regIndex, state.currentValues[regIndex]});
    setCurrentValue(state, regIndex, valueId);
}

void MicroSsaState::setCurrentValue(RenameState& state, const uint32_t regIndex, const uint32_t valueId)
{
    SWC_ASSERT(regIndex < state.currentValues.size());
    state.currentValues[regIndex] = valueId;

    auto& values = reachingValuesByReg_[regIndex];
    // No instruction can observe intermediate restores or phi definitions at
    // the same position. Retain only the final value visible there.
    if (!values.empty() && values.back().position == state.position)
        values.back().valueId = valueId;
    else
        values.push_back(ReachingValue{state.position, valueId});
}

uint32_t MicroSsaState::createValue(const MicroReg reg, const uint32_t blockIndex, const MicroInstrRef instRef, const uint32_t phiIndex)
{
    const uint32_t valueId = valueInfoCount_++;
    if (valueId >= valueInfos_.size())
        valueInfos_.push_back({});

    ValueInfo& info = valueInfos_[valueId];
    info.reg        = reg;
    info.instRef    = instRef;
    info.blockIndex = blockIndex;
    info.phiIndex   = phiIndex;
    info.uses.clear();

    return valueId;
}

uint32_t MicroSsaState::createPhi(const uint32_t blockIndex, const MicroReg reg, const uint32_t regIndex)
{
    BlockInfo&     block    = blocks_[blockIndex];
    const uint32_t phiIndex = phiInfoCount_++;
    if (phiIndex >= phiInfos_.size())
        phiInfos_.push_back({});

    PhiInfo& phi      = phiInfos_[phiIndex];
    phi.reg           = reg;
    phi.regIndex      = regIndex;
    phi.blockIndex    = blockIndex;
    phi.resultValueId = K_INVALID_VALUE;
    phi.predecessorBlocks.clear();
    phi.predecessorBlocks.assign(block.predecessors.begin(), block.predecessors.end());
    phi.incomingValueIds.clear();
    phi.incomingValueIds.resize(phi.predecessorBlocks.size(), K_INVALID_VALUE);
    block.phis.push_back(phiIndex);
    return phiIndex;
}

void MicroSsaState::appendValueUse(const uint32_t valueId, const UseSite& useSite)
{
    SWC_ASSERT(valueId < valueInfoCount_);
    valueInfos_[valueId].uses.push_back(useSite);
}

uint32_t MicroSsaState::transitiveInstructionUseCount(const uint32_t valueId, const uint32_t cap) const
{
    if (valueId >= valueInfoCount_ || cap == 0)
        return 0;

    const auto& uses = valueInfos_[valueId].uses;
    if (uses.empty())
        return 0;
    if (cap == 1 && uses.front().kind == UseSite::Kind::Instruction)
        return 1;

    if (useVisitStamps_.size() < valueInfoCount_)
        useVisitStamps_.resize(valueInfoCount_, 0);
    if (useVisitStamp_ == std::numeric_limits<uint32_t>::max())
    {
        std::ranges::fill(useVisitStamps_, 0);
        useVisitStamp_ = 1;
    }

    const uint32_t visitStamp = useVisitStamp_++;
    useVisitStack_.clear();
    useVisitStack_.push_back(valueId);

    uint32_t count = 0;
    while (!useVisitStack_.empty())
    {
        const uint32_t currentValueId = useVisitStack_.back();
        useVisitStack_.pop_back();

        SWC_ASSERT(currentValueId < valueInfoCount_);
        if (useVisitStamps_[currentValueId] == visitStamp)
            continue;
        useVisitStamps_[currentValueId] = visitStamp;

        const ValueInfo& info = valueInfos_[currentValueId];
        for (const UseSite& useSite : info.uses)
        {
            if (useSite.kind == UseSite::Kind::Instruction)
            {
                if (++count >= cap)
                    return count;
                continue;
            }

            if (useSite.kind != UseSite::Kind::Phi)
                continue;

            const PhiInfo* phi = phiInfo(useSite.phiIndex);
            if (!phi || phi->resultValueId == K_INVALID_VALUE)
                continue;

            useVisitStack_.push_back(phi->resultValueId);
        }
    }

    return count;
}

bool MicroSsaState::isValueTransitivelyUsed(const uint32_t valueId) const
{
    if (valueId >= valueInfoCount_)
        return false;

    const auto& uses = valueInfos_[valueId].uses;
    if (uses.empty())
        return false;
    if (uses.front().kind == UseSite::Kind::Instruction)
        return true;

    if (useVisitStamps_.size() < valueInfoCount_)
        useVisitStamps_.resize(valueInfoCount_, 0);
    if (useVisitStamp_ == std::numeric_limits<uint32_t>::max())
    {
        std::ranges::fill(useVisitStamps_, 0);
        useVisitStamp_ = 1;
    }

    const uint32_t visitStamp = useVisitStamp_++;
    useVisitStack_.clear();
    useVisitStack_.push_back(valueId);

    while (!useVisitStack_.empty())
    {
        const uint32_t currentValueId = useVisitStack_.back();
        useVisitStack_.pop_back();

        SWC_ASSERT(currentValueId < valueInfoCount_);
        if (useVisitStamps_[currentValueId] == visitStamp)
            continue;
        useVisitStamps_[currentValueId] = visitStamp;

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

            useVisitStack_.push_back(phi->resultValueId);
        }
    }

    return false;
}

SWC_END_NAMESPACE();
