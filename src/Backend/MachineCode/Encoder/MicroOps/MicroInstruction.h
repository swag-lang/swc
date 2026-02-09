#pragma once
#include "Backend/MachineCode/Encoder/Core/CpuAbstraction.h"

SWC_BEGIN_NAMESPACE();

// ReSharper disable CppInconsistentNaming
enum class MicroOp : uint8_t
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

struct MicroInstructionOperand
{
    union
    {
        IdentifierRef   name;
        const CallConv* callConv;
        CpuReg          reg;
        CpuOpBits       opBits;
        CpuCond         cpuCond;
        CpuCondJump     jumpType;
        CpuOp           cpuOp;
        uint64_t        value;
    };

    MicroInstructionOperand() :
        value(0)
    {
    }

    MicroInstructionOperand(const MicroInstructionOperand& other)
    {
        std::memcpy(this, &other, sizeof(MicroInstructionOperand));
    }

    MicroInstructionOperand& operator=(const MicroInstructionOperand& other)
    {
        if (this != &other)
            std::memcpy(this, &other, sizeof(MicroInstructionOperand));
        return *this;
    }
};

struct MicroInstruction
{
    MicroInstructionOperand* operands    = nullptr;
    MicroOp                  op          = MicroOp::OpBinaryRI;
    EmitFlags                emitFlags   = EMIT_ZERO;
    uint8_t                  numOperands = 0;

    MicroInstruction() = default;
    ~MicroInstruction() { delete[] operands; }

    MicroInstruction(const MicroInstruction& other)
    {
        copyFrom(other);
    }

    MicroInstruction& operator=(const MicroInstruction& other)
    {
        if (this != &other)
        {
            clear();
            copyFrom(other);
        }

        return *this;
    }

    MicroInstruction(MicroInstruction&& other) noexcept
    {
        moveFrom(other);
    }

    MicroInstruction& operator=(MicroInstruction&& other) noexcept
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
        delete[] operands;
        numOperands = count;
        operands    = count ? new MicroInstructionOperand[count] : nullptr;
    }

    bool isEnd() const { return op == MicroOp::End; }

private:
    void clear()
    {
        delete[] operands;
        operands    = nullptr;
        numOperands = 0;
    }

    void copyFrom(const MicroInstruction& other)
    {
        op          = other.op;
        emitFlags   = other.emitFlags;
        numOperands = other.numOperands;
        if (numOperands)
        {
            operands = new MicroInstructionOperand[numOperands];
            for (uint8_t idx = 0; idx < numOperands; ++idx)
                operands[idx] = other.operands[idx];
        }
        else
        {
            operands = nullptr;
        }
    }

    void moveFrom(MicroInstruction& other)
    {
        op                = other.op;
        emitFlags         = other.emitFlags;
        numOperands       = other.numOperands;
        operands          = other.operands;
        other.numOperands = 0;
        other.operands    = nullptr;
    }
};

SWC_END_NAMESPACE();
