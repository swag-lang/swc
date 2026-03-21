#include "pch.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"

SWC_BEGIN_NAMESPACE();

bool MicroDeadCodeEliminationPass::runForwardPureDefElimination()
{
    SWC_ASSERT(context_ != nullptr);
    SWC_ASSERT(storage_ != nullptr);
    SWC_ASSERT(operands_ != nullptr);

    bool removedAny = false;
    for (auto it = storage_->view().begin(); it != storage_->view().end(); ++it)
    {
        const MicroInstrRef currentRef = it.current;
        const MicroInstr&   inst       = *it;
        const auto*         ops        = inst.ops(*operands_);

        const MicroInstrUseDef useDef = inst.collectUseDef(*operands_, encoder_);
        if (isControlFlowBarrier(inst))
        {
            lastPureDefByReg_.clear();
            continue;
        }

        if (useDef.isCall)
        {
            // Calls consume argument registers and clobber transient registers.
            // The forward local-def map does not model ABI argument uses, so do not
            // propagate pure defs across calls.
            lastPureDefByReg_.clear();
            continue;
        }

        for (const MicroReg useReg : useDef.uses)
            lastPureDefByReg_.erase(useReg);

        for (const MicroReg defReg : useDef.defs)
        {
            if (!canCurrentDefKillPreviousPureDef(inst, ops, defReg))
                continue;

            const auto previousDefIt = lastPureDefByReg_.find(defReg);
            if (previousDefIt != lastPureDefByReg_.end())
            {
                storage_->erase(previousDefIt->second);
                lastPureDefByReg_.erase(previousDefIt);
                removedAny = true;
            }
        }

        const bool trackAsPureDef = isPureDefCandidate(inst, useDef, encoder_, callConvKind_) && !MicroInstrInfo::definesCpuFlags(inst);
        if (trackAsPureDef)
            lastPureDefByReg_[useDef.defs.front()] = currentRef;
    }

    return removedAny;
}

SWC_END_NAMESPACE();
