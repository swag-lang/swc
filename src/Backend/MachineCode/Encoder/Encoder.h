#pragma once
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

    virtual Micro::RegSet getReadRegisters(const MicroInstruction&) { return {}; }
    virtual Micro::RegSet getWriteRegisters(const MicroInstruction&) { return {}; }

    virtual EncodeResult encodeLoadSymbolRelocAddress(Micro::Reg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)                                                                                            = 0;
    virtual EncodeResult encodeLoadSymRelocValue(Micro::Reg reg, uint32_t symbolIndex, uint32_t offset, Micro::OpBits opBits, EmitFlags emitFlags)                                                                           = 0;
    virtual EncodeResult encodePush(Micro::Reg reg, EmitFlags emitFlags)                                                                                                                                                     = 0;
    virtual EncodeResult encodePop(Micro::Reg reg, EmitFlags emitFlags)                                                                                                                                                      = 0;
    virtual EncodeResult encodeNop(EmitFlags emitFlags)                                                                                                                                                                      = 0;
    virtual EncodeResult encodeRet(EmitFlags emitFlags)                                                                                                                                                                      = 0;
    virtual EncodeResult encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)                                                                                                            = 0;
    virtual EncodeResult encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)                                                                                                           = 0;
    virtual EncodeResult encodeCallReg(Micro::Reg reg, const CallConv* callConv, EmitFlags emitFlags)                                                                                                                        = 0;
    virtual EncodeResult encodeJumpTable(Micro::Reg tableReg, Micro::Reg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags)                                                       = 0;
    virtual EncodeResult encodeJump(Micro::Jump& jump, Micro::CondJump jumpType, Micro::OpBits opBits, EmitFlags emitFlags)                                                                                                  = 0;
    virtual EncodeResult encodePatchJump(const Micro::Jump& jump, uint64_t offsetDestination, EmitFlags emitFlags)                                                                                                           = 0;
    virtual EncodeResult encodePatchJump(const Micro::Jump& jump, EmitFlags emitFlags)                                                                                                                                       = 0;
    virtual EncodeResult encodeJumpReg(Micro::Reg reg, EmitFlags emitFlags)                                                                                                                                                  = 0;
    virtual EncodeResult encodeLoadRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits opBits, EmitFlags emitFlags)                                                                                  = 0;
    virtual EncodeResult encodeLoadRegImm(Micro::Reg reg, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags)                                                                                                         = 0;
    virtual EncodeResult encodeLoadRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits opBits, EmitFlags emitFlags)                                                                                                   = 0;
    virtual EncodeResult encodeLoadSignedExtendRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags)                                        = 0;
    virtual EncodeResult encodeLoadSignedExtendRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags)                                                         = 0;
    virtual EncodeResult encodeLoadZeroExtendRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags)                                          = 0;
    virtual EncodeResult encodeLoadZeroExtendRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags)                                                           = 0;
    virtual EncodeResult encodeLoadAddressRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits opBits, EmitFlags emitFlags)                                                                           = 0;
    virtual EncodeResult encodeLoadAmcRegMem(Micro::Reg regDst, Micro::OpBits opBitsDst, Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsSrc, EmitFlags emitFlags)          = 0;
    virtual EncodeResult encodeLoadAmcMemReg(Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsBaseMul, Micro::Reg regSrc, Micro::OpBits opBitsSrc, EmitFlags emitFlags)      = 0;
    virtual EncodeResult encodeLoadAmcMemImm(Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsBaseMul, uint64_t value, Micro::OpBits opBitsValue, EmitFlags emitFlags)       = 0;
    virtual EncodeResult encodeLoadAddressAmcRegMem(Micro::Reg regDst, Micro::OpBits opBitsDst, Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsValue, EmitFlags emitFlags) = 0;
    virtual EncodeResult encodeLoadMemReg(Micro::Reg memReg, uint64_t memOffset, Micro::Reg reg, Micro::OpBits opBits, EmitFlags emitFlags)                                                                                  = 0;
    virtual EncodeResult encodeLoadMemImm(Micro::Reg memReg, uint64_t memOffset, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags)                                                                                  = 0;
    virtual EncodeResult encodeCmpRegReg(Micro::Reg reg0, Micro::Reg reg1, Micro::OpBits opBits, EmitFlags emitFlags)                                                                                                        = 0;
    virtual EncodeResult encodeCmpMemReg(Micro::Reg memReg, uint64_t memOffset, Micro::Reg reg, Micro::OpBits opBits, EmitFlags emitFlags)                                                                                   = 0;
    virtual EncodeResult encodeCmpMemImm(Micro::Reg memReg, uint64_t memOffset, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags)                                                                                   = 0;
    virtual EncodeResult encodeCmpRegImm(Micro::Reg reg, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags)                                                                                                          = 0;
    virtual EncodeResult encodeSetCondReg(Micro::Reg reg, Micro::Cond cpuCond, EmitFlags emitFlags)                                                                                                                          = 0;
    virtual EncodeResult encodeLoadCondRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::Cond setType, Micro::OpBits opBits, EmitFlags emitFlags)                                                                          = 0;
    virtual EncodeResult encodeClearReg(Micro::Reg reg, Micro::OpBits opBits, EmitFlags emitFlags)                                                                                                                           = 0;
    virtual EncodeResult encodeOpUnaryMem(Micro::Reg memReg, uint64_t memOffset, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)                                                                                    = 0;
    virtual EncodeResult encodeOpUnaryReg(Micro::Reg reg, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)                                                                                                           = 0;
    virtual EncodeResult encodeOpBinaryRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)                                                                                 = 0;
    virtual EncodeResult encodeOpBinaryRegMem(Micro::Reg regDst, Micro::Reg memReg, uint64_t memOffset, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)                                                             = 0;
    virtual EncodeResult encodeOpBinaryMemReg(Micro::Reg memReg, uint64_t memOffset, Micro::Reg reg, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)                                                                = 0;
    virtual EncodeResult encodeOpBinaryRegImm(Micro::Reg reg, uint64_t value, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)                                                                                       = 0;
    virtual EncodeResult encodeOpBinaryMemImm(Micro::Reg memReg, uint64_t memOffset, uint64_t value, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)                                                                = 0;
    virtual EncodeResult encodeOpTernaryRegRegReg(Micro::Reg reg0, Micro::Reg reg1, Micro::Reg reg2, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)                                                                = 0;

    void emitLoadSymRelocAddress(Micro::Reg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags = EMIT_ZERO);
    void emitJumpReg(Micro::Reg reg, EmitFlags emitFlags = EMIT_ZERO);
    void emitOpBinaryRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags = EMIT_ZERO);
    void emitOpBinaryRegImm(Micro::Reg reg, uint64_t value, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags = EMIT_ZERO);
    void emitLoadRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits opBits, EmitFlags emitFlags = EMIT_ZERO);
    void emitLoadRegImm(Micro::Reg reg, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags = EMIT_ZERO);
    void emitLoadSignedExtendRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags = EMIT_ZERO);
    void emitLoadZeroExtendRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags = EMIT_ZERO);
    void emitClearReg(Micro::Reg reg, Micro::OpBits opBits, EmitFlags emitFlags = EMIT_ZERO);

    Micro::Symbol* getOrAddSymbol(IdentifierRef name, Micro::SymbolKind kind);
    static void    addSymbolRelocation(uint32_t, uint32_t, uint16_t);

    Store                      store_;
    uint32_t                   textSectionOffset_ = 0;
    uint32_t                   symCsIndex_        = 0;
    BuildParameters            buildParams_;
    Micro::Function*           cpuFct_ = nullptr;
    TaskContext*               ctx_    = nullptr;
    std::vector<Micro::Symbol> symbols_;
};

SWC_END_NAMESPACE();
