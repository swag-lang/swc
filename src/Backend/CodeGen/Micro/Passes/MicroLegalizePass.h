#pragma once
#include "Backend/CodeGen/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroLegalizePass final : public MicroPass
{
public:
    MicroPassKind kind() const override { return MicroPassKind::Legalize; }
    void          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
