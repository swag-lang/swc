#pragma once
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroTypes.h"
#include "Support/Core/Store.h"

SWC_BEGIN_NAMESPACE();

enum class MicroInstrOpcode : uint8_t
{
    End,
    Enter,
    Leave,
    Ignore,
    Label,
    Debug,

    Push,
    Pop,
    Nop,
    Ret,

    SymbolRelocAddr,
    SymbolRelocValue,

    LoadCallParam,
    LoadCallAddrParam,
    LoadCallZeroExtParam,
    StoreCallParam,

    CallLocal,
    CallExtern,
    CallIndirect,

    JumpTable,
    JumpCond,
    JumpReg,
    JumpCondImm,
    PatchJump,

    LoadRegReg,
    LoadRegImm,
    LoadRegMem,
    LoadMemReg,
    LoadMemImm,

    LoadSignedExtRegMem,
    LoadZeroExtRegMem,
    LoadSignedExtRegReg,
    LoadZeroExtRegReg,

    LoadAddrRegMem,

    LoadAmcRegMem,
    LoadAmcMemReg,
    LoadAmcMemImm,
    LoadAddrAmcRegMem,

    CmpRegReg,
    CmpRegImm,
    CmpMemReg,
    CmpMemImm,

    SetCondReg,
    ClearReg,

    OpUnaryMem,
    OpUnaryReg,

    LoadCondRegReg,

    OpBinaryRegReg,
    OpBinaryRegImm,
    OpBinaryRegMem,
    OpBinaryMemReg,
    OpBinaryMemImm,

    OpTernaryRegRegReg,
};

struct MicroInstrOperand
{
    union
    {
        IdentifierRef   name;
        CallConvKind    callConv;
        MicroReg        reg;
        MicroOpBits     opBits;
        MicroCond       cpuCond;
        MicroCondJump   jumpType;
        MicroOp         microOp;
        uint32_t        valueU32;
        int32_t         valueI32;
        uint64_t        valueU64;
    };

    MicroInstrOperand() :
        valueU64(0)
    {
    }

    MicroInstrOperand(const MicroInstrOperand& other)
    {
        std::memcpy(this, &other, sizeof(MicroInstrOperand));
    }

    MicroInstrOperand& operator=(const MicroInstrOperand& other)
    {
        if (this != &other)
            std::memcpy(this, &other, sizeof(MicroInstrOperand));
        return *this;
    }
};

struct MicroInstr
{
    Ref              opsRef      = INVALID_REF;
    MicroInstrOpcode op          = MicroInstrOpcode::OpBinaryRegImm;
    EncodeFlags      emitFlags   = EncodeFlagsE::Zero;
    uint8_t          numOperands = 0;

    MicroInstrOperand* ops(Store& store) const
    {
        if (!numOperands)
            return nullptr;
        return store.ptr<MicroInstrOperand>(opsRef);
    }

    const MicroInstrOperand* ops(const Store& store) const
    {
        if (!numOperands)
            return nullptr;
        return store.ptr<MicroInstrOperand>(opsRef);
    }

    bool isEnd() const { return op == MicroInstrOpcode::End; }
};

SWC_END_NAMESPACE();

