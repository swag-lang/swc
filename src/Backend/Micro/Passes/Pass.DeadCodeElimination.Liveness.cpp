#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroDenseRegIndex.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Support/Core/DenseBits.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_INVALID_DENSE_INDEX = MicroDenseRegIndex::K_INVALID_INDEX;

    void pushDenseRegIndex(SmallVector<uint32_t, 4>& outIndices, MicroDenseRegIndex& denseRegIndex, const MicroReg reg)
    {
        if (!reg.isValid() || reg.isNoBase())
            return;
        outIndices.push_back(denseRegIndex.ensure(reg));
    }
}

bool MicroDeadCodeEliminationPass::eliminateDeadPureDefsByBackwardLivenessCfg(const MicroControlFlowGraph& controlFlowGraph)
{
    SWC_ASSERT(storage_ != nullptr);
    SWC_ASSERT(operands_ != nullptr);

    const std::span<const MicroInstrRef> instructionRefs = controlFlowGraph.instructionRefs();
    if (instructionRefs.empty())
        return false;

    const uint32_t instructionCount = static_cast<uint32_t>(instructionRefs.size());

    cfgInstructionPtrs_.assign(instructionCount, nullptr);

    cfgPureDefCandidateFlags_.assign(instructionCount, 0);
    cfgPureDefDenseDefIndex_.assign(instructionCount, K_INVALID_DENSE_INDEX);

    MicroDenseRegIndex denseRegIndex;
    const size_t       denseReserve = static_cast<size_t>(instructionCount) * 2ull + 8ull;
    denseRegIndex.reserve(denseReserve);

    cfgKillDenseIndices_.resize(instructionCount);
    cfgUseDenseIndices_.resize(instructionCount);
    for (uint32_t i = 0; i < instructionCount; ++i)
    {
        cfgKillDenseIndices_[i].clear();
        cfgUseDenseIndices_[i].clear();
    }

    const CallConv& conv = CallConv::get(callConvKind_);

    for (uint32_t idx = 0; idx < instructionCount; ++idx)
    {
        const MicroInstrRef instructionRef = instructionRefs[idx];
        const MicroInstr*   inst           = storage_->ptr(instructionRef);
        cfgInstructionPtrs_[idx]           = inst;
        if (!inst)
            continue;

        MicroInstrUseDef useDef = inst->collectUseDef(*operands_, encoder_);

        auto& killIndices = cfgKillDenseIndices_[idx];
        auto& useIndices  = cfgUseDenseIndices_[idx];

        if (inst->op == MicroInstrOpcode::Ret)
        {
            pushDenseRegIndex(useIndices, denseRegIndex, conv.intReturn);
            pushDenseRegIndex(useIndices, denseRegIndex, conv.floatReturn);
        }

        if (useDef.isCall)
        {
            const CallConv& convAtCall = CallConv::get(useDef.callConv);
            for (const MicroReg reg : convAtCall.intTransientRegs)
                pushDenseRegIndex(killIndices, denseRegIndex, reg);
            for (const MicroReg reg : convAtCall.floatTransientRegs)
                pushDenseRegIndex(killIndices, denseRegIndex, reg);
            for (const MicroReg reg : convAtCall.intArgRegs)
                pushDenseRegIndex(useIndices, denseRegIndex, reg);
            for (const MicroReg reg : convAtCall.floatArgRegs)
                pushDenseRegIndex(useIndices, denseRegIndex, reg);
            for (const MicroReg reg : useDef.uses)
                pushDenseRegIndex(useIndices, denseRegIndex, reg);
        }
        else
        {
            for (const MicroReg reg : useDef.defs)
                pushDenseRegIndex(killIndices, denseRegIndex, reg);
            for (const MicroReg reg : useDef.uses)
                pushDenseRegIndex(useIndices, denseRegIndex, reg);
        }

        if (isBackwardDeadDefRemovableInstruction(*inst) &&
            isPureDefCandidate(*inst, useDef, encoder_, callConvKind_))
        {
            cfgPureDefCandidateFlags_[idx] = 1;
            cfgPureDefDenseDefIndex_[idx]  = denseRegIndex.ensure(useDef.defs.front());
        }
    }

    const uint32_t rowWordCount = denseRegIndex.wordCount();
    cfgLiveInBits_.assign(static_cast<size_t>(instructionCount) * rowWordCount, 0);

    cfgPredecessors_.resize(instructionCount);
    for (uint32_t idx = 0; idx < instructionCount; ++idx)
    {
        cfgPredecessors_[idx].clear();
        const auto& successors = controlFlowGraph.successors(idx);
        for (const uint32_t successorIdx : successors)
        {
            if (successorIdx >= instructionCount)
                continue;
            cfgPredecessors_[successorIdx].push_back(idx);
        }
    }

    cfgWorklist_.clear();
    cfgWorklist_.reserve(instructionCount);
    cfgInWorklist_.assign(instructionCount, 0);
    for (uint32_t idx = 0; idx < instructionCount; ++idx)
    {
        cfgWorklist_.push_back(idx);
        cfgInWorklist_[idx] = 1;
    }

    cfgTempOut_.assign(rowWordCount, 0);
    cfgTempIn_.assign(rowWordCount, 0);

    const auto computeLiveOut = [&](uint32_t instructionIdx) {
        for (uint64_t& wordBits : cfgTempOut_)
            wordBits = 0;
        for (const uint32_t successorIdx : controlFlowGraph.successors(instructionIdx))
        {
            if (successorIdx >= instructionCount)
                continue;
            const std::span<const uint64_t> successorLiveIn = DenseBits::row(cfgLiveInBits_, successorIdx, rowWordCount);
            for (size_t wordIndex = 0; wordIndex < cfgTempOut_.size(); ++wordIndex)
                cfgTempOut_[wordIndex] |= successorLiveIn[wordIndex];
        }
    };

    while (!cfgWorklist_.empty())
    {
        const uint32_t idx = cfgWorklist_.back();
        cfgWorklist_.pop_back();
        cfgInWorklist_[idx] = 0;

        if (!cfgInstructionPtrs_[idx])
            continue;

        computeLiveOut(idx);

        cfgTempIn_ = cfgTempOut_;
        for (const uint32_t bitIndex : cfgKillDenseIndices_[idx])
            DenseBits::clear(cfgTempIn_, bitIndex);
        for (const uint32_t bitIndex : cfgUseDenseIndices_[idx])
            DenseBits::set(cfgTempIn_, bitIndex);

        if (!DenseBits::copyIfChanged(DenseBits::row(cfgLiveInBits_, idx, rowWordCount), cfgTempIn_))
            continue;

        for (const uint32_t predecessorIdx : cfgPredecessors_[idx])
        {
            if (cfgInWorklist_[predecessorIdx])
                continue;
            cfgWorklist_.push_back(predecessorIdx);
            cfgInWorklist_[predecessorIdx] = 1;
        }
    }

    bool removedAny = false;
    cfgEraseList_.clear();

    for (uint32_t idx = 0; idx < instructionCount; ++idx)
    {
        if (!cfgInstructionPtrs_[idx] || !cfgPureDefCandidateFlags_[idx])
            continue;

        computeLiveOut(idx);

        const uint32_t defDenseIndex = cfgPureDefDenseDefIndex_[idx];
        SWC_ASSERT(defDenseIndex != K_INVALID_DENSE_INDEX);
        if (DenseBits::contains(cfgTempOut_, defDenseIndex))
            continue;

        const MicroInstr* inst = cfgInstructionPtrs_[idx];
        if (inst && MicroInstrInfo::definesCpuFlags(*inst) && !areCpuFlagsDeadAfterInstruction(instructionRefs[idx]))
            continue;

        cfgEraseList_.push_back(instructionRefs[idx]);
    }

    for (const MicroInstrRef eraseRef : cfgEraseList_)
    {
        storage_->erase(eraseRef);
        removedAny = true;
    }

    return removedAny;
}

bool MicroDeadCodeEliminationPass::eliminateDeadPureDefsByBackwardLivenessLinearTail()
{
    SWC_ASSERT(storage_ != nullptr);
    SWC_ASSERT(operands_ != nullptr);

    bool removedAny = false;
    linearLiveRegs_.clear();
    linearLiveRegs_.reserve(64);

    const auto applyLiveness = [&](const MicroInstrUseDef& ud) {
        for (const MicroReg defReg : ud.defs)
            linearLiveRegs_.erase(defReg);
        for (const MicroReg useReg : ud.uses)
            linearLiveRegs_.insert(useReg);
    };

    linearEraseList_.clear();

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

            killCallClobberedRegs(linearLiveRegs_, convAtCall);
            addCallArgumentRegs(linearLiveRegs_, convAtCall);
            for (const MicroReg useReg : useDef.uses)
                linearLiveRegs_.insert(useReg);
            continue;
        }

        if (isControlFlowBarrier(inst))
        {
            linearLiveRegs_.clear();
            if (inst.op == MicroInstrOpcode::Ret)
            {
                processRegion = true;
                addLiveReg(linearLiveRegs_, conv.intReturn);
                addLiveReg(linearLiveRegs_, conv.floatReturn);
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
            applyLiveness(useDef);
            continue;
        }

        const MicroReg defKey = useDef.defs.front();
        if (!linearLiveRegs_.contains(defKey))
        {
            if (MicroInstrInfo::definesCpuFlags(inst) && !areCpuFlagsDeadAfterInstruction(instRef))
            {
                applyLiveness(useDef);
                continue;
            }

            linearEraseList_.push_back(instRef);
            removedAny = true;
            continue;
        }

        applyLiveness(useDef);
    }

    for (const MicroInstrRef ref : linearEraseList_)
        storage_->erase(ref);

    return removedAny;
}

bool MicroDeadCodeEliminationPass::eliminateDeadPureDefsByBackwardLiveness()
{
    SWC_ASSERT(context_ != nullptr);
    SWC_ASSERT(storage_ != nullptr);
    SWC_ASSERT(operands_ != nullptr);

    if (context_->builder)
    {
        const MicroControlFlowGraph& controlFlowGraph = (context_->builder)->controlFlowGraph();
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
