#pragma once
#include "Backend/Micro/MicroPassManager.h"

SWC_BEGIN_NAMESPACE();

class MicroCopyPropagationPass final : public MicroPass
{
public:
    std::string_view name() const override { return "copy-prop"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
