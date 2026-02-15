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

enum class MicroABIPreparedArgKind : uint8_t
{
    Direct          = 0,
    InterfaceObject = 1,
};

struct MicroABIPreparedArg
{
    MicroReg                srcReg  = MicroReg::invalid();
    MicroABIPreparedArgKind kind    = MicroABIPreparedArgKind::Direct;
    bool                    isFloat = false;
    uint8_t                 numBits = 0;
};

struct MicroABICallReturn
{
    void*   valuePtr   = nullptr;
    bool    isVoid     = true;
    bool    isFloat    = false;
    bool    isIndirect = false;
    uint8_t numBits    = 0;
};

uint32_t emitMicroABIPrepareCallArgs(MicroInstrBuilder& builder, CallConvKind callConvKind, std::span<const MicroABIPreparedArg> args);
void     emitMicroABICallByAddress(MicroInstrBuilder& builder, CallConvKind callConvKind, uint64_t targetAddress, std::span<const MicroABICallArg> args, const MicroABICallReturn& ret);
void     emitMicroABICallByReg(MicroInstrBuilder& builder, CallConvKind callConvKind, MicroReg targetReg, uint32_t numPreparedArgs);

SWC_END_NAMESPACE();
