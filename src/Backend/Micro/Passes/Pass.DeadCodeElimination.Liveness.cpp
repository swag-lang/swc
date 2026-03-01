#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_INVALID_DENSE_INDEX = std::numeric_limits<uint32_t>::max();

    uint32_t ensureDenseRegIndex(std::unordered_map<MicroReg, uint32_t>& regToDenseIndex,
                                 std::vector<MicroReg>&                  denseToReg,
                                 const MicroReg                          reg)
    {
        const auto it = regToDenseIndex.find(reg);
        if (it != regToDenseIndex.end())
            return it->second;

        const uint32_t newIndex = static_cast<uint32_t>(denseToReg.size());
        regToDenseIndex.emplace(reg, newIndex);
        denseToReg.push_back(reg);
        return newIndex;
    }

    void pushDenseRegIndex(SmallVector<uint32_t, 4>&               outIndices,
                           std::unordered_map<MicroReg, uint32_t>& regToDenseIndex,
                           std::vector<MicroReg>&                  denseToReg,
                           const MicroReg                          reg)
    {
        if (!reg.isValid() || reg.isNoBase())
            return;
        outIndices.push_back(ensureDenseRegIndex(regToDenseIndex, denseToReg, reg));
    }

    std::span<uint64_t> denseBitRow(std::vector<uint64_t>& bits, const uint32_t rowIndex, const uint32_t rowWordCount)
    {
        if (!rowWordCount)
            return {};

        const size_t offset = static_cast<size_t>(rowIndex) * rowWordCount;
        return {bits.data() + offset, rowWordCount};
    }

    std::span<const uint64_t> denseBitRow(const std::vector<uint64_t>& bits, const uint32_t rowIndex, const uint32_t rowWordCount)
    {
        if (!rowWordCount)
            return {};

        const size_t offset = static_cast<size_t>(rowIndex) * rowWordCount;
        return {bits.data() + offset, rowWordCount};
    }

    void denseBitSet(std::span<uint64_t> bits, const uint32_t bitIndex)
    {
        if (bits.empty())
            return;

        const uint32_t wordIndex = bitIndex >> 6u;
        SWC_ASSERT(wordIndex < bits.size());
        bits[wordIndex] |= (1ull << (bitIndex & 63u));
    }

    void denseBitClear(std::span<uint64_t> bits, const uint32_t bitIndex)
    {
        if (bits.empty())
            return;

        const uint32_t wordIndex = bitIndex >> 6u;
        SWC_ASSERT(wordIndex < bits.size());
        bits[wordIndex] &= ~(1ull << (bitIndex & 63u));
    }

    bool denseBitContains(const std::span<const uint64_t> bits, const uint32_t bitIndex)
    {
        if (bits.empty())
            return false;

        const uint32_t wordIndex = bitIndex >> 6u;
        SWC_ASSERT(wordIndex < bits.size());
        return (bits[wordIndex] & (1ull << (bitIndex & 63u))) != 0;
    }

    bool copyDenseRowIfChanged(std::span<uint64_t> outDst, const std::span<const uint64_t> src)
    {
        SWC_ASSERT(outDst.size() == src.size());
        for (size_t i = 0; i < outDst.size(); ++i)
        {
            if (outDst[i] == src[i])
                continue;

            for (size_t j = 0; j < outDst.size(); ++j)
                outDst[j] = src[j];
            return true;
        }

        return false;
    }
}

bool MicroDeadCodeEliminationPass::eliminateDeadPureDefsByBackwardLivenessCfg(const MicroControlFlowGraph& controlFlowGraph) const
{
    SWC_ASSERT(storage_ != nullptr);
    SWC_ASSERT(operands_ != nullptr);

    const std::span<const MicroInstrRef> instructionRefs = controlFlowGraph.instructionRefs();
    if (instructionRefs.empty())
        return false;

    const uint32_t instructionCount = static_cast<uint32_t>(instructionRefs.size());

    std::vector<const MicroInstr*> instructionPtrs(instructionCount, nullptr);

    std::vector<uint8_t>  pureDefCandidateFlags(instructionCount, 0);
    std::vector<uint32_t> pureDefDenseDefIndex(instructionCount, K_INVALID_DENSE_INDEX);

    std::unordered_map<MicroReg, uint32_t> regToDenseIndex;
    std::vector<MicroReg>                  denseToReg;
    const size_t                           denseReserve = static_cast<size_t>(instructionCount) * 2ull + 8ull;
    regToDenseIndex.reserve(denseReserve);
    denseToReg.reserve(denseReserve);

    std::vector<SmallVector<uint32_t, 4>> killDenseIndices(instructionCount);
    std::vector<SmallVector<uint32_t, 4>> useDenseIndices(instructionCount);

    const CallConv& conv = CallConv::get(callConvKind_);

    for (uint32_t idx = 0; idx < instructionCount; ++idx)
    {
        const MicroInstrRef instructionRef = instructionRefs[idx];
        const MicroInstr*   inst           = storage_->ptr(instructionRef);
        instructionPtrs[idx]               = inst;
        if (!inst)
            continue;

        MicroInstrUseDef useDef = inst->collectUseDef(*operands_, encoder_);

        auto& killIndices = killDenseIndices[idx];
        auto& useIndices  = useDenseIndices[idx];

        if (inst->op == MicroInstrOpcode::Ret)
        {
            pushDenseRegIndex(useIndices, regToDenseIndex, denseToReg, conv.intReturn);
            pushDenseRegIndex(useIndices, regToDenseIndex, denseToReg, conv.floatReturn);
        }

        if (useDef.isCall)
        {
            const CallConv& convAtCall = CallConv::get(useDef.callConv);
            for (const MicroReg reg : convAtCall.intTransientRegs)
                pushDenseRegIndex(killIndices, regToDenseIndex, denseToReg, reg);
            for (const MicroReg reg : convAtCall.floatTransientRegs)
                pushDenseRegIndex(killIndices, regToDenseIndex, denseToReg, reg);
            for (const MicroReg reg : convAtCall.intArgRegs)
                pushDenseRegIndex(useIndices, regToDenseIndex, denseToReg, reg);
            for (const MicroReg reg : convAtCall.floatArgRegs)
                pushDenseRegIndex(useIndices, regToDenseIndex, denseToReg, reg);
            for (const MicroReg reg : useDef.uses)
                pushDenseRegIndex(useIndices, regToDenseIndex, denseToReg, reg);
        }
        else
        {
            for (const MicroReg reg : useDef.defs)
                pushDenseRegIndex(killIndices, regToDenseIndex, denseToReg, reg);
            for (const MicroReg reg : useDef.uses)
                pushDenseRegIndex(useIndices, regToDenseIndex, denseToReg, reg);
        }

        if (isBackwardDeadDefRemovableInstruction(*inst) &&
            isPureDefCandidate(*inst, useDef, encoder_, callConvKind_))
        {
            pureDefCandidateFlags[idx] = 1;
            pureDefDenseDefIndex[idx]  = ensureDenseRegIndex(regToDenseIndex, denseToReg, useDef.defs.front());
        }
    }

    const uint32_t        rowWordCount = static_cast<uint32_t>((denseToReg.size() + 63ull) / 64ull);
    std::vector<uint64_t> liveInBits(static_cast<size_t>(instructionCount) * rowWordCount, 0);

    std::vector<SmallVector<uint32_t>> predecessors(instructionCount);
    for (uint32_t idx = 0; idx < instructionCount; ++idx)
    {
        const SmallVector<uint32_t>& successors = controlFlowGraph.successors(idx);
        for (const uint32_t successorIdx : successors)
        {
            if (successorIdx >= instructionCount)
                continue;
            predecessors[successorIdx].push_back(idx);
        }
    }

    std::vector<uint32_t> worklist;
    worklist.reserve(instructionCount);
    std::vector<uint8_t> inWorklist(instructionCount, 0);
    for (uint32_t idx = 0; idx < instructionCount; ++idx)
    {
        worklist.push_back(idx);
        inWorklist[idx] = 1;
    }

    std::vector<uint64_t> tempOut(rowWordCount, 0);
    std::vector<uint64_t> tempIn(rowWordCount, 0);

    while (!worklist.empty())
    {
        const uint32_t idx = worklist.back();
        worklist.pop_back();
        inWorklist[idx] = 0;

        if (!instructionPtrs[idx])
            continue;

        for (uint64_t& wordBits : tempOut)
            wordBits = 0;

        const SmallVector<uint32_t>& successors = controlFlowGraph.successors(idx);
        for (const uint32_t successorIdx : successors)
        {
            if (successorIdx >= instructionCount)
                continue;

            const std::span<const uint64_t> successorLiveIn = denseBitRow(liveInBits, successorIdx, rowWordCount);
            for (size_t wordIndex = 0; wordIndex < tempOut.size(); ++wordIndex)
                tempOut[wordIndex] |= successorLiveIn[wordIndex];
        }

        tempIn = tempOut;
        for (const uint32_t bitIndex : killDenseIndices[idx])
            denseBitClear(tempIn, bitIndex);
        for (const uint32_t bitIndex : useDenseIndices[idx])
            denseBitSet(tempIn, bitIndex);

        if (!copyDenseRowIfChanged(denseBitRow(liveInBits, idx, rowWordCount), tempIn))
            continue;

        for (const uint32_t predecessorIdx : predecessors[idx])
        {
            if (inWorklist[predecessorIdx])
                continue;
            worklist.push_back(predecessorIdx);
            inWorklist[predecessorIdx] = 1;
        }
    }

    bool                       removedAny = false;
    std::vector<MicroInstrRef> eraseList;
    eraseList.reserve(64);

    for (uint32_t idx = 0; idx < instructionCount; ++idx)
    {
        if (!instructionPtrs[idx] || !pureDefCandidateFlags[idx])
            continue;

        for (uint64_t& wordBits : tempOut)
            wordBits = 0;

        const SmallVector<uint32_t>& successors = controlFlowGraph.successors(idx);
        for (const uint32_t successorIdx : successors)
        {
            if (successorIdx >= instructionCount)
                continue;

            const std::span<const uint64_t> successorLiveIn = denseBitRow(liveInBits, successorIdx, rowWordCount);
            for (size_t wordIndex = 0; wordIndex < tempOut.size(); ++wordIndex)
                tempOut[wordIndex] |= successorLiveIn[wordIndex];
        }

        const uint32_t defDenseIndex = pureDefDenseDefIndex[idx];
        SWC_ASSERT(defDenseIndex != K_INVALID_DENSE_INDEX);
        if (denseBitContains(tempOut, defDenseIndex))
            continue;

        eraseList.push_back(instructionRefs[idx]);
    }

    for (const MicroInstrRef eraseRef : eraseList)
    {
        storage_->erase(eraseRef);
        removedAny = true;
    }

    return removedAny;
}

bool MicroDeadCodeEliminationPass::eliminateDeadPureDefsByBackwardLivenessLinearTail() const
{
    SWC_ASSERT(storage_ != nullptr);
    SWC_ASSERT(operands_ != nullptr);

    bool                         removedAny = false;
    std::unordered_set<MicroReg> liveRegs;
    liveRegs.reserve(64);

    std::vector<MicroInstrRef> eraseList;
    eraseList.reserve(64);

    const CallConv& conv = CallConv::get(callConvKind_);

    bool                     processRegion = false;
    const MicroStorage::View view          = storage_->view();
    for (auto it = view.end(); it != view.begin();)
    {
        --it;
        const MicroInstrRef instRef = it.current;
        const MicroInstr&   inst    = *it;

        const MicroInstrUseDef useDef = inst.collectUseDef(*operands_, encoder_);
        if (useDef.isCall)
        {
            if (!processRegion)
                continue;

            const CallConv& convAtCall = CallConv::get(useDef.callConv);

            killCallClobberedRegs(liveRegs, convAtCall);
            addCallArgumentRegs(liveRegs, convAtCall);
            for (const MicroReg useReg : useDef.uses)
                liveRegs.insert(useReg);
            continue;
        }

        if (isControlFlowBarrier(inst, useDef))
        {
            liveRegs.clear();
            if (inst.op == MicroInstrOpcode::Ret)
            {
                processRegion = true;
                addLiveReg(liveRegs, conv.intReturn);
                addLiveReg(liveRegs, conv.floatReturn);
                continue;
            }

            processRegion = false;
            continue;
        }

        if (!processRegion)
            continue;

        if (!isBackwardDeadDefRemovableInstruction(inst) ||
            !isPureDefCandidate(inst, useDef, encoder_, callConvKind_))
        {
            for (const MicroReg defReg : useDef.defs)
                liveRegs.erase(defReg);
            for (const MicroReg useReg : useDef.uses)
                liveRegs.insert(useReg);
            continue;
        }

        const MicroReg defKey = useDef.defs.front();
        if (!liveRegs.contains(defKey))
        {
            eraseList.push_back(instRef);
            removedAny = true;
            continue;
        }

        for (const MicroReg defReg : useDef.defs)
            liveRegs.erase(defReg);
        for (const MicroReg useReg : useDef.uses)
            liveRegs.insert(useReg);
    }

    for (const MicroInstrRef ref : eraseList)
        storage_->erase(ref);

    return removedAny;
}

bool MicroDeadCodeEliminationPass::eliminateDeadPureDefsByBackwardLiveness() const
{
    SWC_ASSERT(context_ != nullptr);
    SWC_ASSERT(storage_ != nullptr);
    SWC_ASSERT(operands_ != nullptr);

    if (context_->builder)
    {
        const MicroControlFlowGraph& controlFlowGraph = SWC_NOT_NULL(context_->builder)->controlFlowGraph();
        if (!controlFlowGraph.hasUnsupportedControlFlowForCfgLiveness() && controlFlowGraph.supportsDeadCodeLiveness())
        {
            if (eliminateDeadPureDefsByBackwardLivenessCfg(controlFlowGraph))
                return true;

            return eliminateDeadPureDefsByBackwardLivenessLinearTail();
        }
    }

    return eliminateDeadPureDefsByBackwardLivenessLinearTail();
}

SWC_END_NAMESPACE();
