#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.Private.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool eliminateDeadPureDefsByBackwardLivenessCfg(MicroStorage&                storage,
                                                    const MicroOperandStorage&   operands,
                                                    const Encoder*               encoder,
                                                    CallConvKind                 callConvKind,
                                                    const MicroControlFlowGraph& controlFlowGraph)
    {
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
                const MicroInstr*   inst           = storage.ptr(instructionRef);
                if (!inst)
                    continue;

                const MicroInstrUseDef useDef = inst->collectUseDef(operands, encoder);

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
                DeadCodeEliminationPass::transferInstructionLiveness(newLiveIn, newLiveOut, *inst, useDef, callConvKind);

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
            const MicroInstr*   inst           = storage.ptr(instructionRef);
            if (!inst)
                continue;

            const MicroInstrUseDef useDef = inst->collectUseDef(operands, encoder);
            if (!DeadCodeEliminationPass::isBackwardDeadDefRemovableInstruction(*inst) ||
                !DeadCodeEliminationPass::isPureDefCandidate(*inst, useDef, encoder, callConvKind))
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
            storage.erase(eraseRef);
            removedAny = true;
        }

        return removedAny;
    }

    bool eliminateDeadPureDefsByBackwardLivenessLinearTail(MicroStorage& storage, const MicroOperandStorage& operands, const Encoder* encoder, CallConvKind callConvKind)
    {
        bool                         removedAny = false;
        std::unordered_set<MicroReg> liveRegs;
        liveRegs.reserve(64);

        std::vector<MicroInstrRef> eraseList;
        eraseList.reserve(64);

        const CallConv& conv = CallConv::get(callConvKind);

        bool                     processRegion = false;
        const MicroStorage::View view          = storage.view();
        for (auto it = view.end(); it != view.begin();)
        {
            --it;
            const MicroInstrRef instRef = it.current;
            const MicroInstr&   inst    = *it;

            const MicroInstrUseDef useDef = inst.collectUseDef(operands, encoder);
            if (useDef.isCall)
            {
                if (!processRegion)
                    continue;

                const CallConv& convAtCall = CallConv::get(useDef.callConv);

                DeadCodeEliminationPass::killCallClobberedRegs(liveRegs, convAtCall);
                DeadCodeEliminationPass::addCallArgumentRegs(liveRegs, convAtCall);
                for (const MicroReg useReg : useDef.uses)
                    liveRegs.insert(useReg);
                continue;
            }

            if (DeadCodeEliminationPass::isControlFlowBarrier(inst, useDef))
            {
                liveRegs.clear();
                if (inst.op == MicroInstrOpcode::Ret)
                {
                    processRegion = true;
                    DeadCodeEliminationPass::addLiveReg(liveRegs, conv.intReturn);
                    DeadCodeEliminationPass::addLiveReg(liveRegs, conv.floatReturn);
                    continue;
                }

                processRegion = false;
                continue;
            }

            if (!processRegion)
                continue;

            if (!DeadCodeEliminationPass::isBackwardDeadDefRemovableInstruction(inst) ||
                !DeadCodeEliminationPass::isPureDefCandidate(inst, useDef, encoder, callConvKind))
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
            storage.erase(ref);

        return removedAny;
    }
}

namespace DeadCodeEliminationPass
{
    bool eliminateDeadPureDefsByBackwardLiveness(const MicroPassContext& context, MicroStorage& storage, const MicroOperandStorage& operands, const Encoder* encoder, const CallConvKind callConvKind)
    {
        if (context.builder)
        {
            const MicroControlFlowGraph& controlFlowGraph = SWC_NOT_NULL(context.builder)->controlFlowGraph();
            if (!controlFlowGraph.hasUnsupportedControlFlowForCfgLiveness() && controlFlowGraph.supportsDeadCodeLiveness())
            {
                if (eliminateDeadPureDefsByBackwardLivenessCfg(storage, operands, encoder, callConvKind, controlFlowGraph))
                    return true;

                return eliminateDeadPureDefsByBackwardLivenessLinearTail(storage, operands, encoder, callConvKind);
            }
        }

        return eliminateDeadPureDefsByBackwardLivenessLinearTail(storage, operands, encoder, callConvKind);
    }
}

SWC_END_NAMESPACE();
