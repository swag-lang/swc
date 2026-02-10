#pragma once
#include "Backend/MachineCode/Encoder/Encoder.h"
#include "Backend/MachineCode/Micro/MicroInstr.h"
#include "Backend/MachineCode/Micro/MicroInstrPass.h"
#include <vector>

SWC_BEGIN_NAMESPACE();

class Store;
struct MicroJump;

class MicroInstrEncodePass final : public MicroInstrPass
{
public:
    const char* name() const override { return "MicroInstrEncode"; }
    void        run(MicroInstrPassContext& context) override;

private:
    void encodeInstruction(Encoder& encoder, const MicroInstr& inst, Store& store, std::vector<MicroJump>& jumps, size_t idx);
};

SWC_END_NAMESPACE();
