#pragma once
#include "Backend/MachineCode/Micro/Cpu.h"

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
        Cpu::Reg          reg;
        Cpu::OpBits       opBits;
        Cpu::Cond         cpuCond;
        Cpu::CondJump     jumpType;
        Cpu::Op           cpuOp;
        uint32_t        valueU32;
        int32_t         valueI32;
        uint64_t        valueU64;
    };

    MicroInstructionOperand() :
        valueU64(0)
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
    MicroInstructionOperand* ops         = nullptr;
    MicroOp                  op          = MicroOp::OpBinaryRI;
    EmitFlags                emitFlags   = EMIT_ZERO;
    uint8_t                  numOperands = 0;

    MicroInstruction() = default;
    ~MicroInstruction() { delete[] ops; }

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
        SWC_ASSERT(!ops);
        numOperands = count;
        ops         = count ? new MicroInstructionOperand[count] : nullptr;
    }

    bool isEnd() const { return op == MicroOp::End; }

private:
    void clear()
    {
        delete[] ops;
        ops         = nullptr;
        numOperands = 0;
    }

    void copyFrom(const MicroInstruction& other)
    {
        op          = other.op;
        emitFlags   = other.emitFlags;
        numOperands = other.numOperands;
        if (numOperands)
        {
            ops = new MicroInstructionOperand[numOperands];
            for (uint8_t idx = 0; idx < numOperands; ++idx)
                ops[idx] = other.ops[idx];
        }
        else
        {
            ops = nullptr;
        }
    }

    void moveFrom(MicroInstruction& other)
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

