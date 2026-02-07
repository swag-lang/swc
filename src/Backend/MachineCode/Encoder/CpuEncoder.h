#pragma once
#include "Support/Core/Flags.h"
#include "Support/Core/Store.h"
#include "Support/Core/Utf8.h"
#include "Wmf/Module.h"

SWC_BEGIN_NAMESPACE();

enum class OpBits : uint8_t
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

class RegisterSet
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

enum class CpuEmitFlagsE : uint8_t
{
    Zero      = 0,
    Overflow  = 1 << 0,
    Lock      = 1 << 1,
    B64       = 1 << 2,
    CanEncode = 1 << 3,
};

using CpuEmitFlags = EnumFlags<CpuEmitFlagsE>;

constexpr auto EMIT_ZERO       = CpuEmitFlags{};
constexpr auto EMIT_OVERFLOW   = CpuEmitFlagsE::Overflow;
constexpr auto EMIT_LOCK       = CpuEmitFlagsE::Lock;
constexpr auto EMIT_B64        = CpuEmitFlagsE::B64;
constexpr auto EMIT_CAN_ENCODE = CpuEmitFlagsE::CanEncode;

enum class CpuEncodeResult : uint32_t
{
    Zero,
    Left2Reg,
    Left2Rax,
    Right2Reg,
    Right2Rcx,
    Right2Cst,
    ForceZero32,
    NotSupported,
};

struct CpuJump
{
    void*    patchOffsetAddr = nullptr;
    uint64_t offsetStart     = 0;
    OpBits   opBits          = OpBits::Zero;
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

enum class BuildCfgBackendOptim : uint8_t
{
    O0,
    O1,
};

struct BuildParameters
{
    Module*              module   = nullptr;
    BuildCfgBackendOptim optLevel = BuildCfgBackendOptim::O0;
};

struct BackendEncoder
{
    static uint32_t getNumBits(OpBits opBits)
    {
        switch (opBits)
        {
            case OpBits::B8: return 8;
            case OpBits::B16: return 16;
            case OpBits::B32: return 32;
            case OpBits::B64: return 64;
            default: return 0;
        }
    }
};

struct CallConv;
struct MicroInstruction;

class CpuEncoder : public BackendEncoder
{
public:
    virtual ~CpuEncoder() = default;

    static bool isFloat(CpuReg reg) { return reg >= CpuReg::Xmm0 && reg <= CpuReg::Xmm3; }
    static bool isInt(CpuReg reg) { return !isFloat(reg); }

    virtual RegisterSet getReadRegisters(MicroInstruction*) { return {}; }
    virtual RegisterSet getWriteRegisters(MicroInstruction*) { return {}; }

    virtual CpuEncodeResult encodeLoadSymbolRelocAddress(CpuReg reg, uint32_t symbolIndex, uint32_t offset, CpuEmitFlags emitFlags)                                                                      = 0;
    virtual CpuEncodeResult encodeLoadSymRelocValue(CpuReg reg, uint32_t symbolIndex, uint32_t offset, OpBits opBits, CpuEmitFlags emitFlags)                                                            = 0;
    virtual CpuEncodeResult encodePush(CpuReg reg, CpuEmitFlags emitFlags)                                                                                                                               = 0;
    virtual CpuEncodeResult encodePop(CpuReg reg, CpuEmitFlags emitFlags)                                                                                                                                = 0;
    virtual CpuEncodeResult encodeNop(CpuEmitFlags emitFlags)                                                                                                                                            = 0;
    virtual CpuEncodeResult encodeRet(CpuEmitFlags emitFlags)                                                                                                                                            = 0;
    virtual CpuEncodeResult encodeCallLocal(const Utf8& symbolName, const CallConv* callConv, CpuEmitFlags emitFlags)                                                                                    = 0;
    virtual CpuEncodeResult encodeCallExtern(const Utf8& symbolName, const CallConv* callConv, CpuEmitFlags emitFlags)                                                                                   = 0;
    virtual CpuEncodeResult encodeCallReg(CpuReg reg, const CallConv* callConv, CpuEmitFlags emitFlags)                                                                                                  = 0;
    virtual CpuEncodeResult encodeJumpTable(CpuReg tableReg, CpuReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, CpuEmitFlags emitFlags)                                     = 0;
    virtual CpuEncodeResult encodeJump(CpuJump& jump, CpuCondJump jumpType, OpBits opBits, CpuEmitFlags emitFlags)                                                                                       = 0;
    virtual CpuEncodeResult encodePatchJump(const CpuJump& jump, uint64_t offsetDestination, CpuEmitFlags emitFlags)                                                                                     = 0;
    virtual CpuEncodeResult encodePatchJump(const CpuJump& jump, CpuEmitFlags emitFlags)                                                                                                                 = 0;
    virtual CpuEncodeResult encodeJumpReg(CpuReg reg, CpuEmitFlags emitFlags)                                                                                                                            = 0;
    virtual CpuEncodeResult encodeLoadRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits opBits, CpuEmitFlags emitFlags)                                                                       = 0;
    virtual CpuEncodeResult encodeLoadRegImm(CpuReg reg, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)                                                                                          = 0;
    virtual CpuEncodeResult encodeLoadRegReg(CpuReg regDst, CpuReg regSrc, OpBits opBits, CpuEmitFlags emitFlags)                                                                                        = 0;
    virtual CpuEncodeResult encodeLoadSignedExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)                                    = 0;
    virtual CpuEncodeResult encodeLoadSignedExtendRegReg(CpuReg regDst, CpuReg regSrc, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)                                                     = 0;
    virtual CpuEncodeResult encodeLoadZeroExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)                                      = 0;
    virtual CpuEncodeResult encodeLoadZeroExtendRegReg(CpuReg regDst, CpuReg regSrc, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)                                                       = 0;
    virtual CpuEncodeResult encodeLoadAddressRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits opBits, CpuEmitFlags emitFlags)                                                                = 0;
    virtual CpuEncodeResult encodeLoadAmcRegMem(CpuReg regDst, OpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsSrc, CpuEmitFlags emitFlags)          = 0;
    virtual CpuEncodeResult encodeLoadAmcMemReg(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsBaseMul, CpuReg regSrc, OpBits opBitsSrc, CpuEmitFlags emitFlags)      = 0;
    virtual CpuEncodeResult encodeLoadAmcMemImm(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsBaseMul, uint64_t value, OpBits opBitsValue, CpuEmitFlags emitFlags)   = 0;
    virtual CpuEncodeResult encodeLoadAddressAmcRegMem(CpuReg regDst, OpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsValue, CpuEmitFlags emitFlags) = 0;
    virtual CpuEncodeResult encodeLoadMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags)                                                                       = 0;
    virtual CpuEncodeResult encodeLoadMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)                                                                   = 0;
    virtual CpuEncodeResult encodeCmpRegReg(CpuReg reg0, CpuReg reg1, OpBits opBits, CpuEmitFlags emitFlags)                                                                                             = 0;
    virtual CpuEncodeResult encodeCmpMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags)                                                                        = 0;
    virtual CpuEncodeResult encodeCmpMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)                                                                    = 0;
    virtual CpuEncodeResult encodeCmpRegImm(CpuReg reg, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)                                                                                           = 0;
    virtual CpuEncodeResult encodeSetCondReg(CpuReg reg, CpuCond cpuCond, CpuEmitFlags emitFlags)                                                                                                        = 0;
    virtual CpuEncodeResult encodeLoadCondRegReg(CpuReg regDst, CpuReg regSrc, CpuCond setType, OpBits opBits, CpuEmitFlags emitFlags)                                                                   = 0;
    virtual CpuEncodeResult encodeClearReg(CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags)                                                                                                            = 0;
    virtual CpuEncodeResult encodeOpUnaryMem(CpuReg memReg, uint64_t memOffset, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                                         = 0;
    virtual CpuEncodeResult encodeOpUnaryReg(CpuReg reg, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                                                                = 0;
    virtual CpuEncodeResult encodeOpBinaryRegReg(CpuReg regDst, CpuReg regSrc, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                                          = 0;
    virtual CpuEncodeResult encodeOpBinaryRegMem(CpuReg regDst, CpuReg memReg, uint64_t memOffset, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                      = 0;
    virtual CpuEncodeResult encodeOpBinaryMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                         = 0;
    virtual CpuEncodeResult encodeOpBinaryRegImm(CpuReg reg, uint64_t value, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                                            = 0;
    virtual CpuEncodeResult encodeOpBinaryMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                     = 0;
    virtual CpuEncodeResult encodeOpTernaryRegRegReg(CpuReg reg0, CpuReg reg1, CpuReg reg2, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                             = 0;

    void       emitLoadSymRelocAddress(CpuReg reg, uint32_t symbolIndex, uint32_t offset, CpuEmitFlags emitFlags = EMIT_ZERO);
    void       emitJumpReg(CpuReg reg, CpuEmitFlags emitFlags = EMIT_ZERO);
    void       emitOpBinaryRegReg(CpuReg regDst, CpuReg regSrc, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags = EMIT_ZERO);
    void       emitOpBinaryRegImm(CpuReg reg, uint64_t value, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags = EMIT_ZERO);
    void       emitLoadRegReg(CpuReg regDst, CpuReg regSrc, OpBits opBits, CpuEmitFlags emitFlags = EMIT_ZERO);
    void       emitLoadRegImm(CpuReg reg, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags = EMIT_ZERO);
    void       emitLoadSignedExtendRegReg(CpuReg regDst, CpuReg regSrc, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags = EMIT_ZERO);
    void       emitLoadZeroExtendRegReg(CpuReg regDst, CpuReg regSrc, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags = EMIT_ZERO);
    void       emitClearReg(CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags = EMIT_ZERO);
    CpuSymbol* getOrAddSymbol(const Utf8& name, CpuSymbolKind kind);
    void       addSymbolRelocation(uint32_t, uint32_t, uint16_t);

    Store           concat;
    BuildParameters buildParams;
    Module*         module = nullptr;
    CpuFunction*    cpuFct = nullptr;

    BuildCfgBackendOptim optLevel = BuildCfgBackendOptim::O0;

    uint32_t symCsIndex        = 0;
    uint32_t textSectionOffset = 0;

private:
    std::vector<CpuSymbol> symbols_;
};

#ifndef IMAGE_REL_AMD64_ADDR64
#define IMAGE_REL_AMD64_ADDR64 0x0001
#endif
#ifndef IMAGE_REL_AMD64_REL32
#define IMAGE_REL_AMD64_REL32 0x0004
#endif

SWC_END_NAMESPACE();
