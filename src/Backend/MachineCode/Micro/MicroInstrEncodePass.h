#pragma once
#include "Backend/MachineCode/Micro/MicroInstrPass.h"
#include <vector>

SWC_BEGIN_NAMESPACE();

class Store;
struct MicroInstr;
struct MicroJump;

class MicroInstrEncodePass final : public MicroInstrPass
{
public:
    const char* name() const override { return "MicroInstrEncode"; }
    void        run(MicroInstrBuilder& builder, Encoder* encoder) override;

private:
    void                   encodeInstruction(Encoder& encoder, const MicroInstr& inst, const Store& store, size_t idx);
    std::vector<MicroJump> jumps_;
};

SWC_END_NAMESPACE();
