#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroCopyPropagationPass final : public MicroPass
{
public:
    std::string_view name() const override { return "copy-prop"; }
    bool             run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
