#include "pch.h"
#include "Backend/MachineCode/Micro/MicroInstrPass.h"

SWC_BEGIN_NAMESPACE();

void MicroInstrPassManager::add(MicroInstrPass& pass)
{
    passes_.push_back(&pass);
}

void MicroInstrPassManager::run(MicroInstrPassContext& context, TypedStore<MicroInstr>& instructions, TypedStore<MicroInstrOperand>& operands, Encoder* encoder)
{
    context.encoder      = encoder;
    context.instructions = &instructions;
    context.operands     = &operands;

    for (auto* pass : passes_)
    {
        SWC_ASSERT(pass);
        pass->run(context);
    }
}

SWC_END_NAMESPACE();
