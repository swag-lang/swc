#include "pch.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.Private.h"

SWC_BEGIN_NAMESPACE();

namespace DeadCodeEliminationPass
{
    bool runForwardPureDefElimination(const MicroPassContext& context, std::unordered_map<MicroReg, MicroInstrRef>& lastPureDefByReg)
    {
        SWC_ASSERT(context.instructions != nullptr);
        SWC_ASSERT(context.operands != nullptr);

        bool                       removedAny = false;
        MicroStorage&              storage    = *context.instructions;
        const MicroOperandStorage& operands   = *context.operands;
        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            const MicroInstrRef currentRef = it.current;
            const MicroInstr&   inst       = *it;
            const auto* const   ops        = inst.ops(operands);

            const MicroInstrUseDef useDef = inst.collectUseDef(operands, context.encoder);
            if (isControlFlowBarrier(inst, useDef))
            {
                lastPureDefByReg.clear();
                continue;
            }

            if (useDef.isCall)
            {
                // Calls consume argument registers and clobber transient registers.
                // The forward local-def map does not model ABI argument uses, so do not
                // propagate pure defs across calls.
                lastPureDefByReg.clear();
                continue;
            }

            for (const MicroReg useReg : useDef.uses)
                lastPureDefByReg.erase(useReg);

            for (const MicroReg defReg : useDef.defs)
            {
                if (!canCurrentDefKillPreviousPureDef(inst, ops, defReg))
                    continue;

                const auto previousDefIt = lastPureDefByReg.find(defReg);
                if (previousDefIt != lastPureDefByReg.end())
                {
                    storage.erase(previousDefIt->second);
                    lastPureDefByReg.erase(previousDefIt);
                    removedAny = true;
                }
            }

            const bool trackAsPureDef = isPureDefCandidate(inst, useDef, context.encoder, context.callConvKind);
            if (trackAsPureDef)
                lastPureDefByReg[useDef.defs.front()] = currentRef;
        }

        return removedAny;
    }
}

SWC_END_NAMESPACE();
