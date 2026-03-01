#include "pch.h"
#include "Backend/Micro/Passes/Pass.LoadStoreForwarding.Private.h"

SWC_BEGIN_NAMESPACE();

namespace LoadStoreForwardingPass
{
    bool runForwardStoreToLoad(MicroPassContext& context)
    {
        SWC_ASSERT(context.instructions != nullptr);
        SWC_ASSERT(context.operands != nullptr);

        bool                 updated  = false;
        MicroStorage&        storage  = *context.instructions;
        MicroOperandStorage& operands = *context.operands;

        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            const MicroInstr& first = *it;
            if (first.op != MicroInstrOpcode::LoadMemReg && first.op != MicroInstrOpcode::LoadMemImm)
                continue;

            const MicroInstrOperand* firstOps = first.ops(operands);
            if (!firstOps)
                continue;

            for (auto scanIt = std::next(it); scanIt != storage.view().end(); ++scanIt)
            {
                MicroInstr& scanInst = *scanIt;
                if (scanInst.op == MicroInstrOpcode::LoadRegMem)
                {
                    MicroInstrOperand* scanOps = scanInst.ops(operands);
                    if (!scanOps)
                        break;

                    if (first.op == MicroInstrOpcode::LoadMemReg && isSameMemoryAddress(firstOps, scanOps))
                    {
                        scanInst.op          = MicroInstrOpcode::LoadRegReg;
                        scanInst.numOperands = 3;
                        scanOps[1].reg       = firstOps[1].reg;
                        scanOps[2].opBits    = firstOps[2].opBits;
                        updated              = true;
                        break;
                    }

                    if (first.op == MicroInstrOpcode::LoadMemImm &&
                        scanOps[0].reg.isInt() &&
                        isSameMemoryAddressForImmediateStore(firstOps, scanOps))
                    {
                        scanInst.op          = MicroInstrOpcode::LoadRegImm;
                        scanInst.numOperands = 3;
                        scanOps[1].opBits    = firstOps[1].opBits;
                        scanOps[2].valueU64  = firstOps[3].valueU64;
                        updated              = true;
                        break;
                    }
                }

                if (!canCrossInstruction(context, first, firstOps, scanInst))
                    break;
            }
        }

        return updated;
    }
}

SWC_END_NAMESPACE();
