#pragma once
#include "Backend/Micro/MicroPassManager.h"

SWC_BEGIN_NAMESPACE();

class MicroStackAdjustNormalizePass final : public MicroPass
{
public:
    std::string_view name() const override { return "stack-adjust-normalize"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
