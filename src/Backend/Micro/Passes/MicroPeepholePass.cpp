#include "pch.h"

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/Passes/MicroOptimization.h"
#include "Backend/Micro/Passes/MicroPeepholePass.h"

// Performs late local cleanups after allocation/legalization by removing
// instruction forms that are guaranteed to be semantic no-ops.

SWC_BEGIN_NAMESPACE();

bool MicroPeepholePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);
    bool changed = false;

    const MicroStorage::View view = context.instructions->view();
    for (auto it = view.begin(); it != view.end();)
    {
        const Ref                instRef = it.current;
        MicroInstr&              inst    = *it;
        const MicroInstrOperand* ops     = inst.ops(*context.operands);
        ++it;

        if (!MicroOptimization::isNoOpEncoderInstruction(inst, ops))
            continue;

        context.instructions->erase(instRef);
        changed = true;
    }

    return changed;
}

SWC_END_NAMESPACE();
