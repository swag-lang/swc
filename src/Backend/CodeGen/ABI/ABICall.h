#pragma once
#include "Backend/CodeGen/ABI/ABITypeNormalize.h"
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

namespace ABICall
{
    uint32_t computeCallStackAdjust(CallConvKind callConvKind, uint32_t numArgs);

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
    uint32_t prepareArgs(MicroInstrBuilder& builder, CallConvKind callConvKind, std::span<const PreparedArg> args, const ABITypeNormalize::NormalizedType& ret);
    void     materializeValueToReturnRegs(MicroInstrBuilder& builder, CallConvKind callConvKind, MicroReg valueReg, bool valueIsLValue, const ABITypeNormalize::NormalizedType& ret);
    void     storeValueToReturnBuffer(MicroInstrBuilder& builder, CallConvKind callConvKind, MicroReg outputStorageReg, MicroReg valueReg, bool valueIsLValue, const ABITypeNormalize::NormalizedType& ret);
    void     materializeReturnToReg(MicroInstrBuilder& builder, MicroReg dstReg, CallConvKind callConvKind, const ABITypeNormalize::NormalizedType& ret);
    void     callByAddress(MicroInstrBuilder& builder, CallConvKind callConvKind, uint64_t targetAddress, std::span<const Arg> args, const Return& ret);
    void     callByReg(MicroInstrBuilder& builder, CallConvKind callConvKind, MicroReg targetReg, uint32_t numPreparedArgs, const Return& ret, Symbol* callDebugSymbol = nullptr);
    void     callByReg(MicroInstrBuilder& builder, CallConvKind callConvKind, MicroReg targetReg, uint32_t numPreparedArgs, Symbol* callDebugSymbol = nullptr);
    void     callByLocal(MicroInstrBuilder& builder, CallConvKind callConvKind, Symbol* targetSymbol, uint32_t numPreparedArgs, const Return& ret);
    void     callByLocal(MicroInstrBuilder& builder, CallConvKind callConvKind, Symbol* targetSymbol, uint32_t numPreparedArgs);
}

SWC_END_NAMESPACE();
