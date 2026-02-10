#pragma once
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroRegAllocPass final : public MicroPass
{
public:
    const char* name() const override { return "MicroRegAlloc"; }
    void        run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
