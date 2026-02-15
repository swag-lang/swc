#pragma once
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

namespace MicroABICall
{
    struct Arg
    {
        uint64_t value   = 0;
        bool     isFloat = false;
        uint8_t  numBits = 0;
    };

    enum class PreparedArgKind : uint8_t
    {
        Direct          = 0,
        InterfaceObject = 1,
    };

    struct PreparedArg
    {
        MicroReg        srcReg  = MicroReg::invalid();
        PreparedArgKind kind    = PreparedArgKind::Direct;
        bool            isFloat = false;
        uint8_t         numBits = 0;
    };

    struct Return
    {
        void*   valuePtr   = nullptr;
        bool    isVoid     = true;
        bool    isFloat    = false;
        bool    isIndirect = false;
        uint8_t numBits    = 0;
    };

    uint32_t prepareArgs(MicroInstrBuilder& builder, CallConvKind callConvKind, std::span<const PreparedArg> args);
    void     callByAddress(MicroInstrBuilder& builder, CallConvKind callConvKind, uint64_t targetAddress, std::span<const Arg> args, const Return& ret);
    void     callByReg(MicroInstrBuilder& builder, CallConvKind callConvKind, MicroReg targetReg, uint32_t numPreparedArgs);
}

SWC_END_NAMESPACE();
