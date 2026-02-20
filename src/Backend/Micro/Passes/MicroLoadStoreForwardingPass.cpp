#include "pch.h"
#include "Backend/Micro/Passes/MicroLoadStoreForwardingPass.h"

// Forwards a nearby store value directly into a following load from the same
// address, avoiding an unnecessary memory read.

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

        MicroInstrOperand* firstOps  = first.ops(operands);
        MicroInstrOperand* secondOps = second.ops(operands);
        if (first.op == MicroInstrOpcode::LoadMemReg && isSameMemoryAddress(firstOps, secondOps))
        {
            second.op          = MicroInstrOpcode::LoadRegReg;
            second.numOperands = 3;
            secondOps[1].reg   = firstOps[1].reg;
            secondOps[2].opBits = firstOps[2].opBits;
            changed            = true;
        }
        else if (first.op == MicroInstrOpcode::LoadMemImm && isSameMemoryAddressForImmediateStore(firstOps, secondOps))
        {
            second.op           = MicroInstrOpcode::LoadRegImm;
            second.numOperands  = 3;
            secondOps[1].opBits = firstOps[1].opBits;
            secondOps[2].valueU64 = firstOps[3].valueU64;
            changed             = true;
        }
    }

    return changed;
}

SWC_END_NAMESPACE();
