#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroPeepholePass final : public MicroPass
{
public:
    // Removes instruction forms that are guaranteed no-op after regalloc/legalize.
    MicroPassKind kind() const override { return MicroPassKind::Peephole; }
    void          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
