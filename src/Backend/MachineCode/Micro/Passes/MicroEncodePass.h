#pragma once
#include "Backend/MachineCode/Encoder/Encoder.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class PagedStore;
struct MicroJump;

class MicroEncodePass final : public MicroPass
{
public:
    const char* name() const override { return "MicroEncode"; }
    void        run(MicroPassContext& context) override;

private:
    void encodeInstruction(const MicroPassContext& context, const MicroInstr& inst, size_t idx);

    std::vector<MicroJump> jumps_;
};

SWC_END_NAMESPACE();
