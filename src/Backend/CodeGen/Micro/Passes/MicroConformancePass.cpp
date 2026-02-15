#include "pch.h"
#include "Backend/CodeGen/Micro/Passes/MicroConformancePass.h"
#include "Backend/CodeGen/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

void MicroConformancePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.encoder);
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);
    const auto& encoder = *context.encoder;

    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        auto&       inst = *it;
        auto* const ops  = inst.ops(*context.operands);
        encoder.conformInstruction(inst, ops);
    }
}

SWC_END_NAMESPACE();
