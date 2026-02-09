#pragma once
#include "Backend/MachineCode/Encoder/Core/CpuAbstraction.h"
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

class Encoder
{
public:
    explicit Encoder(TaskContext& ctx) :
        ctx_(&ctx)
    {
    }
    virtual ~Encoder() = default;

    TaskContext&       ctx() { return *ctx_; }
    const TaskContext& ctx() const { return *ctx_; }

    static bool isFloat(CpuReg reg) { return reg >= CpuReg::Xmm0 && reg <= CpuReg::Xmm3; }
    static bool isInt(CpuReg reg) { return !isFloat(reg); }

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

    virtual CpuRegSet getReadRegisters(const MicroInstruction&) { return {}; }
    virtual CpuRegSet getWriteRegisters(const MicroInstruction&) { return {}; }

    virtual EncodeResult encodeLoadSymbolRelocAddress(TaskContext& ctx, CpuReg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)                                                                            = 0;
    virtual EncodeResult encodeLoadSymRelocValue(TaskContext& ctx, CpuReg reg, uint32_t symbolIndex, uint32_t offset, CpuOpBits opBits, EmitFlags emitFlags)                                                               = 0;
    virtual EncodeResult encodePush(TaskContext& ctx, CpuReg reg, EmitFlags emitFlags)                                                                                                                                     = 0;
    virtual EncodeResult encodePop(TaskContext& ctx, CpuReg reg, EmitFlags emitFlags)                                                                                                                                      = 0;
    virtual EncodeResult encodeNop(TaskContext& ctx, EmitFlags emitFlags)                                                                                                                                                  = 0;
    virtual EncodeResult encodeRet(TaskContext& ctx, EmitFlags emitFlags)                                                                                                                                                  = 0;
    virtual EncodeResult encodeCallLocal(TaskContext& ctx, IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)                                                                                        = 0;
    virtual EncodeResult encodeCallExtern(TaskContext& ctx, IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)                                                                                       = 0;
    virtual EncodeResult encodeCallReg(TaskContext& ctx, CpuReg reg, const CallConv* callConv, EmitFlags emitFlags)                                                                                                        = 0;
    virtual EncodeResult encodeJumpTable(TaskContext& ctx, CpuReg tableReg, CpuReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags)                                           = 0;
    virtual EncodeResult encodeJump(TaskContext& ctx, CpuJump& jump, CpuCondJump jumpType, CpuOpBits opBits, EmitFlags emitFlags)                                                                                          = 0;
    virtual EncodeResult encodePatchJump(TaskContext& ctx, const CpuJump& jump, uint64_t offsetDestination, EmitFlags emitFlags)                                                                                           = 0;
    virtual EncodeResult encodePatchJump(TaskContext& ctx, const CpuJump& jump, EmitFlags emitFlags)                                                                                                                       = 0;
    virtual EncodeResult encodeJumpReg(TaskContext& ctx, CpuReg reg, EmitFlags emitFlags)                                                                                                                                  = 0;
    virtual EncodeResult encodeLoadRegMem(TaskContext& ctx, CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits opBits, EmitFlags emitFlags)                                                                          = 0;
    virtual EncodeResult encodeLoadRegImm(TaskContext& ctx, CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)                                                                                             = 0;
    virtual EncodeResult encodeLoadRegReg(TaskContext& ctx, CpuReg regDst, CpuReg regSrc, CpuOpBits opBits, EmitFlags emitFlags)                                                                                           = 0;
    virtual EncodeResult encodeLoadSignedExtendRegMem(TaskContext& ctx, CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)                                    = 0;
    virtual EncodeResult encodeLoadSignedExtendRegReg(TaskContext& ctx, CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)                                                     = 0;
    virtual EncodeResult encodeLoadZeroExtendRegMem(TaskContext& ctx, CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)                                      = 0;
    virtual EncodeResult encodeLoadZeroExtendRegReg(TaskContext& ctx, CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)                                                       = 0;
    virtual EncodeResult encodeLoadAddressRegMem(TaskContext& ctx, CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits opBits, EmitFlags emitFlags)                                                                   = 0;
    virtual EncodeResult encodeLoadAmcRegMem(TaskContext& ctx, CpuReg regDst, CpuOpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsSrc, EmitFlags emitFlags)          = 0;
    virtual EncodeResult encodeLoadAmcMemReg(TaskContext& ctx, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsBaseMul, CpuReg regSrc, CpuOpBits opBitsSrc, EmitFlags emitFlags)      = 0;
    virtual EncodeResult encodeLoadAmcMemImm(TaskContext& ctx, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsBaseMul, uint64_t value, CpuOpBits opBitsValue, EmitFlags emitFlags)   = 0;
    virtual EncodeResult encodeLoadAddressAmcRegMem(TaskContext& ctx, CpuReg regDst, CpuOpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsValue, EmitFlags emitFlags) = 0;
    virtual EncodeResult encodeLoadMemReg(TaskContext& ctx, CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)                                                                          = 0;
    virtual EncodeResult encodeLoadMemImm(TaskContext& ctx, CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)                                                                      = 0;
    virtual EncodeResult encodeCmpRegReg(TaskContext& ctx, CpuReg reg0, CpuReg reg1, CpuOpBits opBits, EmitFlags emitFlags)                                                                                                = 0;
    virtual EncodeResult encodeCmpMemReg(TaskContext& ctx, CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)                                                                           = 0;
    virtual EncodeResult encodeCmpMemImm(TaskContext& ctx, CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)                                                                       = 0;
    virtual EncodeResult encodeCmpRegImm(TaskContext& ctx, CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)                                                                                              = 0;
    virtual EncodeResult encodeSetCondReg(TaskContext& ctx, CpuReg reg, CpuCond cpuCond, EmitFlags emitFlags)                                                                                                              = 0;
    virtual EncodeResult encodeLoadCondRegReg(TaskContext& ctx, CpuReg regDst, CpuReg regSrc, CpuCond setType, CpuOpBits opBits, EmitFlags emitFlags)                                                                      = 0;
    virtual EncodeResult encodeClearReg(TaskContext& ctx, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)                                                                                                               = 0;
    virtual EncodeResult encodeOpUnaryMem(TaskContext& ctx, CpuReg memReg, uint64_t memOffset, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)                                                                            = 0;
    virtual EncodeResult encodeOpUnaryReg(TaskContext& ctx, CpuReg reg, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)                                                                                                   = 0;
    virtual EncodeResult encodeOpBinaryRegReg(TaskContext& ctx, CpuReg regDst, CpuReg regSrc, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)                                                                             = 0;
    virtual EncodeResult encodeOpBinaryRegMem(TaskContext& ctx, CpuReg regDst, CpuReg memReg, uint64_t memOffset, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)                                                         = 0;
    virtual EncodeResult encodeOpBinaryMemReg(TaskContext& ctx, CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)                                                            = 0;
    virtual EncodeResult encodeOpBinaryRegImm(TaskContext& ctx, CpuReg reg, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)                                                                               = 0;
    virtual EncodeResult encodeOpBinaryMemImm(TaskContext& ctx, CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)                                                        = 0;
    virtual EncodeResult encodeOpTernaryRegRegReg(TaskContext& ctx, CpuReg reg0, CpuReg reg1, CpuReg reg2, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)                                                                = 0;

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

protected:
    TaskContext*    ctx_ = nullptr;
    Store           store_;
    BuildParameters buildParams_;
    Module*         module_            = nullptr;
    CpuFunction*    cpuFct_            = nullptr;
    uint32_t        symCsIndex_        = 0;
    uint32_t        textSectionOffset_ = 0;

private:
    std::vector<CpuSymbol> symbols_;
};

SWC_END_NAMESPACE();
