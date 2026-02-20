#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroInstructionCombinePass final : public MicroPass
{
public:
    // Merge adjacent immediate operations on the same destination register.
    MicroPassKind kind() const override { return MicroPassKind::InstructionCombine; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
