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
        struct CallName
        {
            uint32_t        nameIndex;
            const CallConv* cc;
        } callName;

        struct CallReg
        {
            CpuReg          regA;
            const CallConv* cc;
        } callReg;

        struct Reg
        {
            CpuReg regA;
        } reg;

        struct RegOpBits
        {
            CpuReg    regA;
            CpuOpBits opBitsA;
        } regOpBits;

        struct RegValue
        {
            CpuReg   regA;
            uint64_t valueA;
        } regValue;

        struct RegValueOpBits
        {
            CpuReg    regA;
            CpuOpBits opBitsA;
            uint64_t  valueA;
        } regValueOpBits;

        struct RegValue2
        {
            CpuReg   regA;
            uint64_t valueA;
            uint64_t valueB;
        } regValue2;

        struct RegValue2OpBits
        {
            CpuReg    regA;
            CpuOpBits opBitsA;
            uint64_t  valueA;
            uint64_t  valueB;
        } regValue2OpBits;

        struct RegReg
        {
            CpuReg regA;
            CpuReg regB;
        } regReg;

        struct RegRegOpBits
        {
            CpuReg    regA;
            CpuReg    regB;
            CpuOpBits opBitsA;
        } regRegOpBits;

        struct RegRegOpBits2
        {
            CpuReg    regA;
            CpuReg    regB;
            CpuOpBits opBitsA;
            CpuOpBits opBitsB;
        } regRegOpBits2;

        struct RegRegValueOpBits
        {
            CpuReg    regA;
            CpuReg    regB;
            CpuOpBits opBitsA;
            uint64_t  valueA;
        } regRegValueOpBits;

        struct RegRegValueOpBits2
        {
            CpuReg    regA;
            CpuReg    regB;
            CpuOpBits opBitsA;
            CpuOpBits opBitsB;
            uint64_t  valueA;
        } regRegValueOpBits2;

        struct RegCond
        {
            CpuReg  regA;
            CpuCond cpuCond;
        } regCond;

        struct RegRegCondOpBits
        {
            CpuReg    regA;
            CpuReg    regB;
            CpuCond   cpuCond;
            CpuOpBits opBitsA;
        } regRegCondOpBits;

        struct RegOpBitsCpuOp
        {
            CpuReg    regA;
            CpuOpBits opBitsA;
            CpuOp     cpuOp;
        } regOpBitsCpuOp;

        struct RegValueOpBitsCpuOp
        {
            CpuReg    regA;
            CpuOpBits opBitsA;
            CpuOp     cpuOp;
            uint64_t  valueA;
        } regValueOpBitsCpuOp;

        struct RegValue2OpBitsCpuOp
        {
            CpuReg    regA;
            CpuOpBits opBitsA;
            CpuOp     cpuOp;
            uint64_t  valueA;
            uint64_t  valueB;
        } regValue2OpBitsCpuOp;

        struct RegRegOpBitsCpuOp
        {
            CpuReg    regA;
            CpuReg    regB;
            CpuOpBits opBitsA;
            CpuOp     cpuOp;
        } regRegOpBitsCpuOp;

        struct RegRegValueOpBitsCpuOp
        {
            CpuReg    regA;
            CpuReg    regB;
            CpuOpBits opBitsA;
            CpuOp     cpuOp;
            uint64_t  valueA;
        } regRegValueOpBitsCpuOp;

        struct JumpCond
        {
            CpuCondJump jumpType;
            CpuOpBits   opBitsA;
        } jumpCond;

        struct JumpCondImm
        {
            CpuCondJump jumpType;
            CpuOpBits   opBitsA;
            uint64_t    valueA;
        } jumpCondImm;

        struct JumpTable
        {
            CpuReg   regA;
            CpuReg   regB;
            uint64_t valueA;
            uint64_t valueB;
            uint64_t valueC;
        } jumpTable;

        struct PatchJump
        {
            uint64_t valueA;
            uint64_t valueB;
            uint64_t valueC;
        } patchJump;

        struct Amc
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

        struct Ternary
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
