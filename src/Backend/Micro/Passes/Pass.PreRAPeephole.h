#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroPreRaPeepholePass final : public MicroPass
{
public:
    std::string_view name() const override { return "pre-ra-peephole"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
