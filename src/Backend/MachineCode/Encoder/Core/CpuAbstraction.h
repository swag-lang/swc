#pragma once
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

enum class CpuOpBits : uint8_t
{
    Zero = 0,
    B8   = 8,
    B16  = 16,
    B32  = 32,
    B64  = 64,
    B128 = 128,
};

enum class CpuReg : uint8_t
{
    Rax,
    Rbx,
    Rcx,
    Rdx,
    Rsp,
    Rbp,
    Rsi,
    Rdi,
    R8,
    R9,
    R10,
    R11,
    R12,
    R13,
    R14,
    R15,
    Xmm0,
    Xmm1,
    Xmm2,
    Xmm3,
    Rip,
    Max,
};

class CpuRegSet
{
public:
    void add(CpuReg reg)
    {
        const auto idx = static_cast<size_t>(reg);
        if (idx < bits_.size())
            bits_.set(idx);
    }

    bool has(CpuReg reg) const
    {
        const auto idx = static_cast<size_t>(reg);
        return idx < bits_.size() && bits_.test(idx);
    }

    void clear() { bits_.reset(); }

private:
    std::bitset<64> bits_{};
};

// ReSharper disable CppInconsistentNaming
enum class CpuOp : uint8_t
{
    ADD      = 0x01,
    OR       = 0x09,
    AND      = 0x21,
    SUB      = 0x29,
    CVTI2F   = 0x2A,
    CVTU2F64 = 0x2B,
    CVTF2I   = 0x2C,
    XOR      = 0x31,
    FSQRT    = 0x51,
    FAND     = 0x54,
    FXOR     = 0x57,
    FADD     = 0x58,
    FMUL     = 0x59,
    CVTF2F   = 0x5A,
    FSUB     = 0x5C,
    FMIN     = 0x5D,
    FDIV     = 0x5E,
    FMAX     = 0x5F,
    MOVSXD   = 0x63,
    XCHG     = 0x87,
    MOV      = 0x8B,
    LEA      = 0x8D,
    NEG      = 0x9F,
    BSWAP    = 0xB0,
    POPCNT   = 0xB8,
    BSF      = 0xBC,
    BSR      = 0xBD,
    MUL      = 0xC0,
    IMUL     = 0xC1,
    ROL      = 0xC7,
    ROR      = 0xC8,
    SHL      = 0xE0,
    SHR      = 0xE8,
    SAL      = 0xF0,
    DIV      = 0xF1,
    MOD      = 0xF3,
    NOT      = 0xF7,
    SAR      = 0xF8,
    IDIV     = 0xF9,
    CMPXCHG  = 0xFA,
    IMOD     = 0xFB,
    MULADD   = 0xFC,
};

enum class CpuCond : uint8_t
{
    A,
    O,
    AE,
    G,
    B,
    BE,
    E,
    GE,
    L,
    LE,
    NA,
    NE,
    P,
    NP,
    EP,
    NEP,
};

enum class CpuCondJump : uint8_t
{
    JNO,
    JNZ,
    JZ,
    JL,
    JLE,
    JB,
    JBE,
    JGE,
    JAE,
    JG,
    JA,
    JP,
    JS,
    JNP,
    JUMP,
};
// ReSharper restore CppInconsistentNaming

struct CpuJump
{
    void*     patchOffsetAddr = nullptr;
    uint64_t  offsetStart     = 0;
    CpuOpBits opBits          = CpuOpBits::Zero;
};

struct CpuLabelToSolve
{
    uint32_t ipDest = 0;
    CpuJump  jump{};
};

enum class CpuSymbolKind
{
    Function,
    Extern,
    Custom,
    Constant,
};

struct CpuSymbol
{
    Utf8          name;
    CpuSymbolKind kind  = CpuSymbolKind::Custom;
    uint32_t      value = 0;
    uint32_t      index = 0;
};

struct CpuFunction
{
    uint32_t                     symbolIndex  = 0;
    uint32_t                     startAddress = 0;
    std::vector<CpuLabelToSolve> labelsToSolve;
};

#ifndef IMAGE_REL_AMD64_ADDR64
#define IMAGE_REL_AMD64_ADDR64 0x0001
#endif
#ifndef IMAGE_REL_AMD64_REL32
#define IMAGE_REL_AMD64_REL32 0x0004
#endif

SWC_END_NAMESPACE();
