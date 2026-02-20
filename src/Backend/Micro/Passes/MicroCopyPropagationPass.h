#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroCopyPropagationPass final : public MicroPass
{
public:
    // Propagate register copies forward and rewrite later pure uses.
    MicroPassKind kind() const override { return MicroPassKind::CopyPropagation; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
