#include "pch.h"

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/Passes/MicroPeepholePass.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isNoOpRegisterMove(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (inst.op != MicroInstrOpcode::LoadRegReg || !ops || inst.numOperands < 2)
            return false;

        return ops[0].reg == ops[1].reg;
    }

    bool isNoOpRegAddSubImm(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (inst.op != MicroInstrOpcode::OpBinaryRegImm || !ops || inst.numOperands < 4)
            return false;

        if (ops[3].valueU64 != 0)
            return false;

        const MicroOp op = ops[2].microOp;
        return op == MicroOp::Add || op == MicroOp::Subtract;
    }
}

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

        if (!isNoOpRegisterMove(inst, ops) && !isNoOpRegAddSubImm(inst, ops))
            continue;

        context.instructions->erase(instRef);
    }
}

SWC_END_NAMESPACE();
