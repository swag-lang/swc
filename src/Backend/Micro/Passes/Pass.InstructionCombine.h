#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Pre-RA instruction combining on virtual registers.
// Merges nearby operations on the same destination into a single operation.
class MicroInstructionCombinePass final : public MicroPass
{
public:
    std::string_view name() const override { return "instcombine"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
