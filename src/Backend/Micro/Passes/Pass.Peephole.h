#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroPeepholePass final : public MicroPass
{
public:
    std::string_view name() const override { return "peephole"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
