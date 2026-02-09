#pragma once
#include "Backend/MachineCode/Micro/Cpu.h"
#include "Runtime/Runtime.h"
#include "Support/Core/Store.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
struct MicroInstruction;
struct Module;
struct CallConv;

struct BuildParameters
{
    Module*                       module   = nullptr;
    Runtime::BuildCfgBackendOptim optLevel = Runtime::BuildCfgBackendOptim::O0;
};

enum class EmitFlagsE : uint8_t
{
    Zero      = 0,
    Overflow  = 1 << 0,
    Lock      = 1 << 1,
    B64       = 1 << 2,
    CanEncode = 1 << 3,
};
using EmitFlags = EnumFlags<EmitFlagsE>;

constexpr auto EMIT_ZERO       = EmitFlags{};
constexpr auto EMIT_OVERFLOW   = EmitFlagsE::Overflow;
constexpr auto EMIT_LOCK       = EmitFlagsE::Lock;
constexpr auto EMIT_B64        = EmitFlagsE::B64;
constexpr auto EMIT_CAN_ENCODE = EmitFlagsE::CanEncode;

enum class EncodeResult : uint32_t
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

static bool isFloat(CpuReg reg)
{
    return reg >= CpuReg::Xmm0 && reg <= CpuReg::Xmm3;
}
static bool isInt(CpuReg reg)
{
    return !isFloat(reg);
}

static uint32_t getNumBits(CpuOpBits opBits)
{
    switch (opBits)
    {
        case CpuOpBits::B8: return 8;
        case CpuOpBits::B16: return 16;
        case CpuOpBits::B32: return 32;
        case CpuOpBits::B64: return 64;
        default: return 0;
    }
}

class Encoder
{
    friend class MicroInstructionBuilder;

protected:
    TaskContext&       ctx() { return *ctx_; }
    const TaskContext& ctx() const { return *ctx_; }

    explicit Encoder(TaskContext& ctx) :
        ctx_(&ctx)
    {
    }
    virtual ~Encoder() = default;

    virtual CpuRegSet getReadRegisters(const MicroInstruction&) { return {}; }
    virtual CpuRegSet getWriteRegisters(const MicroInstruction&) { return {}; }

    virtual EncodeResult encodeLoadSymbolRelocAddress(CpuReg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)                                                                            = 0;
    virtual EncodeResult encodeLoadSymRelocValue(CpuReg reg, uint32_t symbolIndex, uint32_t offset, CpuOpBits opBits, EmitFlags emitFlags)                                                               = 0;
    virtual EncodeResult encodePush(CpuReg reg, EmitFlags emitFlags)                                                                                                                                     = 0;
    virtual EncodeResult encodePop(CpuReg reg, EmitFlags emitFlags)                                                                                                                                      = 0;
    virtual EncodeResult encodeNop(EmitFlags emitFlags)                                                                                                                                                  = 0;
    virtual EncodeResult encodeRet(EmitFlags emitFlags)                                                                                                                                                  = 0;
    virtual EncodeResult encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)                                                                                        = 0;
    virtual EncodeResult encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)                                                                                       = 0;
    virtual EncodeResult encodeCallReg(CpuReg reg, const CallConv* callConv, EmitFlags emitFlags)                                                                                                        = 0;
    virtual EncodeResult encodeJumpTable(CpuReg tableReg, CpuReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags)                                           = 0;
    virtual EncodeResult encodeJump(CpuJump& jump, CpuCondJump jumpType, CpuOpBits opBits, EmitFlags emitFlags)                                                                                          = 0;
    virtual EncodeResult encodePatchJump(const CpuJump& jump, uint64_t offsetDestination, EmitFlags emitFlags)                                                                                           = 0;
    virtual EncodeResult encodePatchJump(const CpuJump& jump, EmitFlags emitFlags)                                                                                                                       = 0;
    virtual EncodeResult encodeJumpReg(CpuReg reg, EmitFlags emitFlags)                                                                                                                                  = 0;
    virtual EncodeResult encodeLoadRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits opBits, EmitFlags emitFlags)                                                                          = 0;
    virtual EncodeResult encodeLoadRegImm(CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)                                                                                             = 0;
    virtual EncodeResult encodeLoadRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits opBits, EmitFlags emitFlags)                                                                                           = 0;
    virtual EncodeResult encodeLoadSignedExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)                                    = 0;
    virtual EncodeResult encodeLoadSignedExtendRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)                                                     = 0;
    virtual EncodeResult encodeLoadZeroExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)                                      = 0;
    virtual EncodeResult encodeLoadZeroExtendRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)                                                       = 0;
    virtual EncodeResult encodeLoadAddressRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits opBits, EmitFlags emitFlags)                                                                   = 0;
    virtual EncodeResult encodeLoadAmcRegMem(CpuReg regDst, CpuOpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsSrc, EmitFlags emitFlags)          = 0;
    virtual EncodeResult encodeLoadAmcMemReg(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsBaseMul, CpuReg regSrc, CpuOpBits opBitsSrc, EmitFlags emitFlags)      = 0;
    virtual EncodeResult encodeLoadAmcMemImm(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsBaseMul, uint64_t value, CpuOpBits opBitsValue, EmitFlags emitFlags)   = 0;
    virtual EncodeResult encodeLoadAddressAmcRegMem(CpuReg regDst, CpuOpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsValue, EmitFlags emitFlags) = 0;
    virtual EncodeResult encodeLoadMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)                                                                          = 0;
    virtual EncodeResult encodeLoadMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)                                                                      = 0;
    virtual EncodeResult encodeCmpRegReg(CpuReg reg0, CpuReg reg1, CpuOpBits opBits, EmitFlags emitFlags)                                                                                                = 0;
    virtual EncodeResult encodeCmpMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)                                                                           = 0;
    virtual EncodeResult encodeCmpMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)                                                                       = 0;
    virtual EncodeResult encodeCmpRegImm(CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)                                                                                              = 0;
    virtual EncodeResult encodeSetCondReg(CpuReg reg, CpuCond cpuCond, EmitFlags emitFlags)                                                                                                              = 0;
    virtual EncodeResult encodeLoadCondRegReg(CpuReg regDst, CpuReg regSrc, CpuCond setType, CpuOpBits opBits, EmitFlags emitFlags)                                                                      = 0;
    virtual EncodeResult encodeClearReg(CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)                                                                                                               = 0;
    virtual EncodeResult encodeOpUnaryMem(CpuReg memReg, uint64_t memOffset, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)                                                                            = 0;
    virtual EncodeResult encodeOpUnaryReg(CpuReg reg, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)                                                                                                   = 0;
    virtual EncodeResult encodeOpBinaryRegReg(CpuReg regDst, CpuReg regSrc, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)                                                                             = 0;
    virtual EncodeResult encodeOpBinaryRegMem(CpuReg regDst, CpuReg memReg, uint64_t memOffset, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)                                                         = 0;
    virtual EncodeResult encodeOpBinaryMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)                                                            = 0;
    virtual EncodeResult encodeOpBinaryRegImm(CpuReg reg, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)                                                                               = 0;
    virtual EncodeResult encodeOpBinaryMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)                                                        = 0;
    virtual EncodeResult encodeOpTernaryRegRegReg(CpuReg reg0, CpuReg reg1, CpuReg reg2, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)                                                                = 0;

    void emitLoadSymRelocAddress(CpuReg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags = EMIT_ZERO);
    void emitJumpReg(CpuReg reg, EmitFlags emitFlags = EMIT_ZERO);
    void emitOpBinaryRegReg(CpuReg regDst, CpuReg regSrc, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags = EMIT_ZERO);
    void emitOpBinaryRegImm(CpuReg reg, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags = EMIT_ZERO);
    void emitLoadRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits opBits, EmitFlags emitFlags = EMIT_ZERO);
    void emitLoadRegImm(CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags = EMIT_ZERO);
    void emitLoadSignedExtendRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags = EMIT_ZERO);
    void emitLoadZeroExtendRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags = EMIT_ZERO);
    void emitClearReg(CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags = EMIT_ZERO);

    CpuSymbol*  getOrAddSymbol(IdentifierRef name, CpuSymbolKind kind);
    static void addSymbolRelocation(uint32_t, uint32_t, uint16_t);

    Store                  store_;
    uint32_t               textSectionOffset_ = 0;
    uint32_t               symCsIndex_        = 0;
    BuildParameters        buildParams_;
    CpuFunction*           cpuFct_ = nullptr;
    TaskContext*           ctx_    = nullptr;
    std::vector<CpuSymbol> symbols_;
};

SWC_END_NAMESPACE();
