#include "pch.h"

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/Passes/MicroOptimizationHelpers.h"
#include "Backend/Micro/Passes/MicroPeepholePass.h"

SWC_BEGIN_NAMESPACE();

void MicroPeepholePass::run(MicroPassContext& context)
{
    if (context.builder->backendBuildCfg().optimizeLevel == Runtime::BuildCfgBackendOptim::O0)
        return;

    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);

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
    }
}

SWC_END_NAMESPACE();
