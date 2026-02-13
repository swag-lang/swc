#pragma once
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroRegAllocPass final : public MicroPass
{
public:
    void run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
