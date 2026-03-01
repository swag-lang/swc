#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"

SWC_BEGIN_NAMESPACE();

bool MicroDeadCodeEliminationPass::eliminateDeadPureDefsByBackwardLivenessCfg(const MicroControlFlowGraph& controlFlowGraph) const
{
    SWC_ASSERT(storage_ != nullptr);
    SWC_ASSERT(operands_ != nullptr);

    const std::span<const MicroInstrRef> instructionRefs = controlFlowGraph.instructionRefs();
    if (instructionRefs.empty())
        return false;

    const size_t                              instructionCount = instructionRefs.size();
    std::vector<std::unordered_set<MicroReg>> liveIn(instructionCount);
    std::vector<std::unordered_set<MicroReg>> liveOut(instructionCount);
    bool                                      dataflowUpdated = true;
    while (dataflowUpdated)
    {
        dataflowUpdated = false;

        for (size_t i = instructionCount; i > 0; --i)
        {
            const size_t        idx            = i - 1;
            const MicroInstrRef instructionRef = instructionRefs[idx];
            const MicroInstr*   inst           = storage_->ptr(instructionRef);
            if (!inst)
                continue;

            const MicroInstrUseDef useDef = inst->collectUseDef(*operands_, encoder_);

            std::unordered_set<MicroReg> newLiveOut;
            const SmallVector<uint32_t>& successors = controlFlowGraph.successors(static_cast<uint32_t>(idx));
            for (const uint32_t successorIndexRef : successors)
            {
                const size_t successorIndex = successorIndexRef;
                if (successorIndex >= liveIn.size())
                    continue;

                const std::unordered_set<MicroReg>& successorLiveIn = liveIn[successorIndex];
                for (const MicroReg reg : successorLiveIn)
                    newLiveOut.insert(reg);
            }

            std::unordered_set<MicroReg> newLiveIn;
            transferInstructionLiveness(newLiveIn, newLiveOut, *inst, useDef, callConvKind_);

            if (newLiveOut != liveOut[idx] || newLiveIn != liveIn[idx])
            {
                liveOut[idx]    = std::move(newLiveOut);
                liveIn[idx]     = std::move(newLiveIn);
                dataflowUpdated = true;
            }
        }
    }

    bool                       removedAny = false;
    std::vector<MicroInstrRef> eraseList;
    eraseList.reserve(64);

    for (size_t i = 0; i < instructionCount; ++i)
    {
        const MicroInstrRef instructionRef = instructionRefs[i];
        const MicroInstr*   inst           = storage_->ptr(instructionRef);
        if (!inst)
            continue;

        const MicroInstrUseDef useDef = inst->collectUseDef(*operands_, encoder_);
        if (!isBackwardDeadDefRemovableInstruction(*inst) ||
            !isPureDefCandidate(*inst, useDef, encoder_, callConvKind_))
        {
            continue;
        }

        const MicroReg defRegKey = useDef.defs.front();
        if (liveOut[i].contains(defRegKey))
            continue;

        eraseList.push_back(instructionRef);
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

bool MicroDeadCodeEliminationPass::eliminateDeadPureDefsByBackwardLiveness()
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
