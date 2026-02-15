#pragma once
#include "Backend/MachineCode/Encoder/Encoder.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

struct MicroJump;

class MicroEncodePass final : public MicroPass
{
public:
    MicroPassKind kind() const override { return MicroPassKind::Encode; }
    void run(MicroPassContext& context) override;

private:
    void encodeInstruction(const MicroPassContext& context, const MicroInstr& inst, Ref instRef);

    std::unordered_map<Ref, MicroJump> jumps_;
};

SWC_END_NAMESPACE();
