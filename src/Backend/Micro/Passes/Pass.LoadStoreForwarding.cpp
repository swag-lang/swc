#include "pch.h"
#include "Backend/Micro/Passes/Pass.LoadStoreForwarding.h"

// Forwards recent store values into matching following loads.
// Example: store [rbp+8], r1; load r2, [rbp+8] -> mov r2, r1.
// Example: store [rbp+8], 5;  load r2, [rbp+8] -> load r2, 5.
// This removes redundant memory traffic when aliasing is provably safe.

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isSameMemoryAddress(const MicroInstrOperand* storeOps, const MicroInstrOperand* loadOps)
    {
        return storeOps[0].reg == loadOps[1].reg &&
               storeOps[3].valueU64 == loadOps[3].valueU64 &&
               storeOps[2].opBits == loadOps[2].opBits;
    }

    bool isSameMemoryAddressForImmediateStore(const MicroInstrOperand* storeOps, const MicroInstrOperand* loadOps)
    {
        return storeOps[0].reg == loadOps[1].reg &&
               storeOps[2].valueU64 == loadOps[3].valueU64 &&
               storeOps[1].opBits == loadOps[2].opBits;
    }
}

bool MicroLoadStoreForwardingPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool                 changed  = false;
    MicroStorage&        storage  = *SWC_CHECK_NOT_NULL(context.instructions);
    MicroOperandStorage& operands = *SWC_CHECK_NOT_NULL(context.operands);

    for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
    {
        auto nextIt = it;
        ++nextIt;
        if (nextIt == storage.view().end())
            break;

        MicroInstr& first  = *it;
        MicroInstr& second = *nextIt;
        if (second.op != MicroInstrOpcode::LoadRegMem)
            continue;

        const MicroInstrOperand* firstOps  = first.ops(operands);
        MicroInstrOperand*       secondOps = second.ops(operands);
        if (first.op == MicroInstrOpcode::LoadMemReg && isSameMemoryAddress(firstOps, secondOps))
        {
            second.op           = MicroInstrOpcode::LoadRegReg;
            second.numOperands  = 3;
            secondOps[1].reg    = firstOps[1].reg;
            secondOps[2].opBits = firstOps[2].opBits;
            changed             = true;
        }
        else if (first.op == MicroInstrOpcode::LoadMemImm && isSameMemoryAddressForImmediateStore(firstOps, secondOps))
        {
            second.op             = MicroInstrOpcode::LoadRegImm;
            second.numOperands    = 3;
            secondOps[1].opBits   = firstOps[1].opBits;
            secondOps[2].valueU64 = firstOps[3].valueU64;
            changed               = true;
        }
    }

    return changed;
}

SWC_END_NAMESPACE();
