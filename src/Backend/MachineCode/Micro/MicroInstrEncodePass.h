#pragma once
#include "Backend/MachineCode/Encoder/Encoder.h"
#include "Backend/MachineCode/Micro/MicroInstr.h"
#include "Backend/MachineCode/Micro/MicroInstrPass.h"
#include "Support/Core/TypedStore.h"
#include <vector>

SWC_BEGIN_NAMESPACE();

class Store;
struct MicroJump;

class MicroInstrEncodePass final : public MicroInstrPass
{
public:
    MicroInstrEncodePass(TypedStore<MicroInstr>& instructions, TypedStore<MicroInstrOperand>& operands);

    const char* name() const override { return "MicroInstrEncode"; }
    void        run(Encoder* encoder) override;

private:
    void encodeInstruction(Encoder& encoder, const MicroInstr& inst, Store& store, std::vector<MicroJump>& jumps, size_t idx);

    TypedStore<MicroInstr>&        instructions_;
    TypedStore<MicroInstrOperand>& operands_;
};

SWC_END_NAMESPACE();
