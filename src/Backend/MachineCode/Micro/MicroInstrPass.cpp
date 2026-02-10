#include "pch.h"
#include "Backend/MachineCode/Micro/MicroInstrPass.h"

SWC_BEGIN_NAMESPACE();

void MicroInstrPassManager::add(MicroInstrPass& pass)
{
    passes_.push_back(&pass);
}

void MicroInstrPassManager::run(MicroInstrBuilder& builder, Encoder* encoder)
{
    for (auto* pass : passes_)
    {
        SWC_ASSERT(pass);
        pass->run(builder, encoder);
    }
}

SWC_END_NAMESPACE();
