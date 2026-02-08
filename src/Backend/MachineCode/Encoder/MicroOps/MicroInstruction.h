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

struct MicroInstruction
{
    MicroOp   op        = MicroOp::OpBinaryRI;
    EmitFlags emitFlags = EMIT_ZERO;

    union
    {
        struct
        {
            IdentifierRef   name;
            const CallConv* cc;
        } callName;

        struct
        {
            CpuReg          regA;
            const CallConv* cc;
        } callReg;

        struct
        {
            CpuReg regA;
        } reg;

        struct
        {
            CpuReg    regA;
            CpuOpBits opBitsA;
        } regOpBits;

        struct
        {
            CpuReg   regA;
            uint64_t valueA;
        } regValue;

        struct
        {
            CpuReg    regA;
            CpuOpBits opBitsA;
            uint64_t  valueA;
        } regValueOpBits;

        struct
        {
            CpuReg   regA;
            uint64_t valueA;
            uint64_t valueB;
        } regValue2;

        struct
        {
            CpuReg    regA;
            CpuOpBits opBitsA;
            uint64_t  valueA;
            uint64_t  valueB;
        } regValue2OpBits;

        struct
        {
            CpuReg regA;
            CpuReg regB;
        } regReg;

        struct
        {
            CpuReg    regA;
            CpuReg    regB;
            CpuOpBits opBitsA;
        } regRegOpBits;

        struct
        {
            CpuReg    regA;
            CpuReg    regB;
            CpuOpBits opBitsA;
            CpuOpBits opBitsB;
        } regRegOpBits2;

        struct
        {
            CpuReg    regA;
            CpuReg    regB;
            CpuOpBits opBitsA;
            uint64_t  valueA;
        } regRegValueOpBits;

        struct
        {
            CpuReg    regA;
            CpuReg    regB;
            CpuOpBits opBitsA;
            CpuOpBits opBitsB;
            uint64_t  valueA;
        } regRegValueOpBits2;

        struct
        {
            CpuReg  regA;
            CpuCond cpuCond;
        } regCond;

        struct
        {
            CpuReg    regA;
            CpuReg    regB;
            CpuCond   cpuCond;
            CpuOpBits opBitsA;
        } regRegCondOpBits;

        struct
        {
            CpuReg    regA;
            CpuOpBits opBitsA;
            CpuOp     cpuOp;
        } regOpBitsCpuOp;

        struct
        {
            CpuReg    regA;
            CpuOpBits opBitsA;
            CpuOp     cpuOp;
            uint64_t  valueA;
        } regValueOpBitsCpuOp;

        struct
        {
            CpuReg    regA;
            CpuOpBits opBitsA;
            CpuOp     cpuOp;
            uint64_t  valueA;
            uint64_t  valueB;
        } regValue2OpBitsCpuOp;

        struct
        {
            CpuReg    regA;
            CpuReg    regB;
            CpuOpBits opBitsA;
            CpuOp     cpuOp;
        } regRegOpBitsCpuOp;

        struct
        {
            CpuReg    regA;
            CpuReg    regB;
            CpuOpBits opBitsA;
            CpuOp     cpuOp;
            uint64_t  valueA;
        } regRegValueOpBitsCpuOp;

        struct
        {
            CpuCondJump jumpType;
            CpuOpBits   opBitsA;
        } jumpCond;

        struct
        {
            CpuCondJump jumpType;
            CpuOpBits   opBitsA;
            uint64_t    valueA;
        } jumpCondImm;

        struct
        {
            CpuReg   regA;
            CpuReg   regB;
            uint64_t valueA;
            uint64_t valueB;
            uint64_t valueC;
        } jumpTable;

        struct
        {
            uint64_t valueA;
            uint64_t valueB;
            uint64_t valueC;
        } patchJump;

        struct
        {
            CpuReg    regA;
            CpuReg    regB;
            CpuReg    regC;
            CpuOpBits opBitsA;
            CpuOpBits opBitsB;
            uint64_t  valueA;
            uint64_t  valueB;
            uint64_t  valueC;
        } amc;

        struct
        {
            CpuReg    regA;
            CpuReg    regB;
            CpuReg    regC;
            CpuOpBits opBitsA;
            CpuOp     cpuOp;
        } ternary;
    } payload;

    bool isEnd() const { return op == MicroOp::End; }
};

SWC_END_NAMESPACE();
