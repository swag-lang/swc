#pragma once
#include "Backend/MachineCode/Encoder/Encoder.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"
#include <unordered_map>

SWC_BEGIN_NAMESPACE();

struct MicroJump;

class MicroEncodePass final : public MicroPass
{
public:
    void run(MicroPassContext& context) override;

private:
    void encodeInstruction(const MicroPassContext& context, const MicroInstr& inst, Ref instRef);

    std::unordered_map<Ref, MicroJump> jumps_;
};

SWC_END_NAMESPACE();
