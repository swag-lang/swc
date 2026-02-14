#pragma once
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

struct MicroABICallArg
{
    uint64_t value   = 0;
    bool     isFloat = false;
    uint8_t  numBits = 0;
};

struct MicroABICallReturn
{
    void*   valuePtr   = nullptr;
    bool    isVoid     = true;
    bool    isFloat    = false;
    bool    isIndirect = false;
    uint8_t numBits    = 0;
};

void emitMicroABICallByAddress(MicroInstrBuilder& builder, CallConvKind callConvKind, uint64_t targetAddress, std::span<const MicroABICallArg> args, const MicroABICallReturn& ret);

SWC_END_NAMESPACE();
