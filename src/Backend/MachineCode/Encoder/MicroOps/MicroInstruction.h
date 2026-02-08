#pragma once
#include "Backend/MachineCode/Encoder/Core/CpuEncoder.h"

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

struct MicroInstruction
{
    Utf8 name;

    union
    {
        uint64_t        valueA = 0;
        const CallConv* cc;
    };

    uint64_t valueB = 0;
    uint64_t valueC = 0;

    MicroOp     op       = MicroOp::OpBinaryRI;
    CpuOp       cpuOp    = CpuOp::ADD;
    CpuCond     cpuCond  = CpuCond::A;
    CpuCondJump jumpType = CpuCondJump::JUMP;

    OpBits       opBitsA   = OpBits::Zero;
    OpBits       opBitsB   = OpBits::Zero;
    CpuEmitFlags emitFlags = EMIT_ZERO;

    CpuReg regA = CpuReg::Rax;
    CpuReg regB = CpuReg::Rax;
    CpuReg regC = CpuReg::Rax;

    bool isEnd() const { return op == MicroOp::End; }
};

SWC_END_NAMESPACE();
