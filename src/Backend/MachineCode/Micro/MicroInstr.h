#pragma once
#include "Backend/MachineCode/Micro/MicroTypes.h"

SWC_BEGIN_NAMESPACE();

// ReSharper disable CppInconsistentNaming
enum class MicroInstrKind : uint8_t
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
    JumpM,
    JumpCondI,
    PatchJump,

    LoadRR,
    LoadRI,
    LoadRM,
    LoadMR,
    LoadMI,

    LoadSignedExtRM,
    LoadZeroExtRM,
    LoadSignedExtRR,
    LoadZeroExtRR,

    LoadAddrRM,

    LoadAmcRM,
    LoadAmcMR,
    LoadAmcMI,
    LoadAddrAmcRM,

    CmpRR,
    CmpRI,
    CmpMR,
    CmpMI,

    SetCondR,
    ClearR,

    OpUnaryM,
    OpUnaryR,

    LoadCondRR,

    OpBinaryRR,
    OpBinaryRI,
    OpBinaryRM,
    OpBinaryMR,
    OpBinaryMI,

    OpTernaryRRR,
};
// ReSharper restore CppInconsistentNaming

struct MicroInstrOperand
{
    union
    {
        IdentifierRef   name;
        const CallConv* callConv;
        MicroReg        reg;
        MicroOpBits     opBits;
        MicroCond       cpuCond;
        MicroCondJump   jumpType;
        MicroOp         cpuOp;
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
    MicroInstrOperand* ops         = nullptr;
    MicroInstrKind     op          = MicroInstrKind::OpBinaryRI;
    EncodeFlags        emitFlags   = EMIT_ZERO;
    uint8_t            numOperands = 0;

    MicroInstr() = default;
    ~MicroInstr() { delete[] ops; }

    MicroInstr(const MicroInstr& other)
    {
        copyFrom(other);
    }

    MicroInstr& operator=(const MicroInstr& other)
    {
        if (this != &other)
        {
            clear();
            copyFrom(other);
        }

        return *this;
    }

    MicroInstr(MicroInstr&& other) noexcept
    {
        moveFrom(other);
    }

    MicroInstr& operator=(MicroInstr&& other) noexcept
    {
        if (this != &other)
        {
            clear();
            moveFrom(other);
        }

        return *this;
    }

    void allocateOperands(uint8_t count)
    {
        SWC_ASSERT(!ops);
        numOperands = count;
        ops         = count ? new MicroInstrOperand[count] : nullptr;
    }

    bool isEnd() const { return op == MicroInstrKind::End; }

private:
    void clear()
    {
        delete[] ops;
        ops         = nullptr;
        numOperands = 0;
    }

    void copyFrom(const MicroInstr& other)
    {
        op          = other.op;
        emitFlags   = other.emitFlags;
        numOperands = other.numOperands;
        if (numOperands)
        {
            ops = new MicroInstrOperand[numOperands];
            for (uint8_t idx = 0; idx < numOperands; ++idx)
                ops[idx] = other.ops[idx];
        }
        else
        {
            ops = nullptr;
        }
    }

    void moveFrom(MicroInstr& other)
    {
        op                = other.op;
        emitFlags         = other.emitFlags;
        numOperands       = other.numOperands;
        ops               = other.ops;
        other.numOperands = 0;
        other.ops         = nullptr;
    }
};

SWC_END_NAMESPACE();
