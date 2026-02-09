#pragma once
#include "Backend/MachineCode/Encoder/EncoderTypes.h"
#include "Backend/MachineCode/Micro/Micro.h"
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
    friend class MicroInstructionBuilder;

protected:
    TaskContext&       ctx() { return *ctx_; }
    const TaskContext& ctx() const { return *ctx_; }

    explicit Encoder(TaskContext& ctx) :
        ctx_(&ctx)
    {
    }
    virtual ~Encoder() = default;

    virtual MicroRegSet getReadRegisters(const MicroInstruction&) { return {}; }
    virtual MicroRegSet getWriteRegisters(const MicroInstruction&) { return {}; }

    virtual EncodeResult encodeLoadSymbolRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)                                                                                                                = 0;
    virtual EncodeResult encodeLoadSymRelocValue(MicroReg reg, uint32_t symbolIndex, uint32_t offset, MicroOpBits opBits, EmitFlags emitFlags)                                                                                          = 0;
    virtual EncodeResult encodePush(MicroReg reg, EmitFlags emitFlags)                                                                                                                                                                         = 0;
    virtual EncodeResult encodePop(MicroReg reg, EmitFlags emitFlags)                                                                                                                                                                          = 0;
    virtual EncodeResult encodeNop(EmitFlags emitFlags)                                                                                                                                                                                               = 0;
    virtual EncodeResult encodeRet(EmitFlags emitFlags)                                                                                                                                                                                               = 0;
    virtual EncodeResult encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)                                                                                                                                     = 0;
    virtual EncodeResult encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)                                                                                                                                    = 0;
    virtual EncodeResult encodeCallReg(MicroReg reg, const CallConv* callConv, EmitFlags emitFlags)                                                                                                                                            = 0;
    virtual EncodeResult encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags)                                                                      = 0;
    virtual EncodeResult encodeJump(MicroJump& jump, MicroCondJump jumpType, MicroOpBits opBits, EmitFlags emitFlags)                                                                                                            = 0;
    virtual EncodeResult encodePatchJump(const MicroJump& jump, uint64_t offsetDestination, EmitFlags emitFlags)                                                                                                                               = 0;
    virtual EncodeResult encodePatchJump(const MicroJump& jump, EmitFlags emitFlags)                                                                                                                                                           = 0;
    virtual EncodeResult encodeJumpReg(MicroReg reg, EmitFlags emitFlags)                                                                                                                                                                      = 0;
    virtual EncodeResult encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EmitFlags emitFlags)                                                                                            = 0;
    virtual EncodeResult encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags)                                                                                                                        = 0;
    virtual EncodeResult encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EmitFlags emitFlags)                                                                                                             = 0;
    virtual EncodeResult encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags)                                             = 0;
    virtual EncodeResult encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags)                                                              = 0;
    virtual EncodeResult encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags)                                               = 0;
    virtual EncodeResult encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags)                                                                = 0;
    virtual EncodeResult encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EmitFlags emitFlags)                                                                                     = 0;
    virtual EncodeResult encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc, EmitFlags emitFlags)          = 0;
    virtual EncodeResult encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc, EmitFlags emitFlags)      = 0;
    virtual EncodeResult encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EmitFlags emitFlags)            = 0;
    virtual EncodeResult encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue, EmitFlags emitFlags) = 0;
    virtual EncodeResult encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EmitFlags emitFlags)                                                                                            = 0;
    virtual EncodeResult encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags)                                                                                                 = 0;
    virtual EncodeResult encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits, EmitFlags emitFlags)                                                                                                                  = 0;
    virtual EncodeResult encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EmitFlags emitFlags)                                                                                             = 0;
    virtual EncodeResult encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags)                                                                                                  = 0;
    virtual EncodeResult encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags)                                                                                                                         = 0;
    virtual EncodeResult encodeSetCondReg(MicroReg reg, MicroCond cpuCond, EmitFlags emitFlags)                                                                                                                                         = 0;
    virtual EncodeResult encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits, EmitFlags emitFlags)                                                                               = 0;
    virtual EncodeResult encodeClearReg(MicroReg reg, MicroOpBits opBits, EmitFlags emitFlags)                                                                                                                                          = 0;
    virtual EncodeResult encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)                                                                                              = 0;
    virtual EncodeResult encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)                                                                                                                     = 0;
    virtual EncodeResult encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)                                                                                      = 0;
    virtual EncodeResult encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)                                                                  = 0;
    virtual EncodeResult encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)                                                                     = 0;
    virtual EncodeResult encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)                                                                                                 = 0;
    virtual EncodeResult encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)                                                                          = 0;
    virtual EncodeResult encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)                                                                = 0;

    void emitLoadSymRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags = EMIT_ZERO);
    void emitJumpReg(MicroReg reg, EmitFlags emitFlags = EMIT_ZERO);
    void emitOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags = EMIT_ZERO);
    void emitOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags = EMIT_ZERO);
    void emitLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EmitFlags emitFlags = EMIT_ZERO);
    void emitLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags = EMIT_ZERO);
    void emitLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags = EMIT_ZERO);
    void emitLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags = EMIT_ZERO);
    void emitClearReg(MicroReg reg, MicroOpBits opBits, EmitFlags emitFlags = EMIT_ZERO);

    EncoderSymbol* getOrAddSymbol(IdentifierRef name, EncoderSymbolKind kind);
    static void         addSymbolRelocation(uint32_t, uint32_t, uint16_t);

    Store                           store_;
    uint32_t                        textSectionOffset_ = 0;
    uint32_t                        symCsIndex_        = 0;
    BuildParameters                 buildParams_;
    EncoderFunction*         cpuFct_ = nullptr;
    TaskContext*                    ctx_    = nullptr;
    std::vector<EncoderSymbol> symbols_;
};

SWC_END_NAMESPACE();
