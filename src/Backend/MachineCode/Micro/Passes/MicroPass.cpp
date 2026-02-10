#include "pch.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

void MicroPassManager::add(MicroPass& pass)
{
    passes_.push_back(&pass);
}

void MicroPassManager::run(MicroPassContext& context) const
{
    for (auto* pass : passes_)
    {
        SWC_ASSERT(pass);
        pass->run(context);
    }
}

SWC_END_NAMESPACE();
