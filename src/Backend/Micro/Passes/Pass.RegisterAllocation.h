#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroRegisterAllocationPass final : public MicroPass
{
public:
    std::string_view  name() const override { return "regalloc"; }
    MicroRegPrintMode printModeBefore() const override { return MicroRegPrintMode::Virtual; }
    bool              run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
