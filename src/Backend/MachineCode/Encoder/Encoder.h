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

    virtual Cpu::RegSet getReadRegisters(const MicroInstruction&) { return {}; }
    virtual Cpu::RegSet getWriteRegisters(const MicroInstruction&) { return {}; }

    virtual EncodeResult encodeLoadSymbolRelocAddress(Cpu::Reg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)                                                                                    = 0;
    virtual EncodeResult encodeLoadSymRelocValue(Cpu::Reg reg, uint32_t symbolIndex, uint32_t offset, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                     = 0;
    virtual EncodeResult encodePush(Cpu::Reg reg, EmitFlags emitFlags)                                                                                                                                             = 0;
    virtual EncodeResult encodePop(Cpu::Reg reg, EmitFlags emitFlags)                                                                                                                                              = 0;
    virtual EncodeResult encodeNop(EmitFlags emitFlags)                                                                                                                                                            = 0;
    virtual EncodeResult encodeRet(EmitFlags emitFlags)                                                                                                                                                            = 0;
    virtual EncodeResult encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)                                                                                                  = 0;
    virtual EncodeResult encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)                                                                                                 = 0;
    virtual EncodeResult encodeCallReg(Cpu::Reg reg, const CallConv* callConv, EmitFlags emitFlags)                                                                                                                = 0;
    virtual EncodeResult encodeJumpTable(Cpu::Reg tableReg, Cpu::Reg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags)                                                 = 0;
    virtual EncodeResult encodeJump(Cpu::Jump& jump, Cpu::CondJump jumpType, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                                              = 0;
    virtual EncodeResult encodePatchJump(const Cpu::Jump& jump, uint64_t offsetDestination, EmitFlags emitFlags)                                                                                                   = 0;
    virtual EncodeResult encodePatchJump(const Cpu::Jump& jump, EmitFlags emitFlags)                                                                                                                               = 0;
    virtual EncodeResult encodeJumpReg(Cpu::Reg reg, EmitFlags emitFlags)                                                                                                                                          = 0;
    virtual EncodeResult encodeLoadRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                              = 0;
    virtual EncodeResult encodeLoadRegImm(Cpu::Reg reg, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                                                   = 0;
    virtual EncodeResult encodeLoadRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                                               = 0;
    virtual EncodeResult encodeLoadSignedExtendRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags)                                      = 0;
    virtual EncodeResult encodeLoadSignedExtendRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags)                                                       = 0;
    virtual EncodeResult encodeLoadZeroExtendRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags)                                        = 0;
    virtual EncodeResult encodeLoadZeroExtendRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags)                                                         = 0;
    virtual EncodeResult encodeLoadAddressRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                       = 0;
    virtual EncodeResult encodeLoadAmcRegMem(Cpu::Reg regDst, Cpu::OpBits opBitsDst, Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsSrc, EmitFlags emitFlags)          = 0;
    virtual EncodeResult encodeLoadAmcMemReg(Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsBaseMul, Cpu::Reg regSrc, Cpu::OpBits opBitsSrc, EmitFlags emitFlags)      = 0;
    virtual EncodeResult encodeLoadAmcMemImm(Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsBaseMul, uint64_t value, Cpu::OpBits opBitsValue, EmitFlags emitFlags)     = 0;
    virtual EncodeResult encodeLoadAddressAmcRegMem(Cpu::Reg regDst, Cpu::OpBits opBitsDst, Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsValue, EmitFlags emitFlags) = 0;
    virtual EncodeResult encodeLoadMemReg(Cpu::Reg memReg, uint64_t memOffset, Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                              = 0;
    virtual EncodeResult encodeLoadMemImm(Cpu::Reg memReg, uint64_t memOffset, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                            = 0;
    virtual EncodeResult encodeCmpRegReg(Cpu::Reg reg0, Cpu::Reg reg1, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                                                    = 0;
    virtual EncodeResult encodeCmpMemReg(Cpu::Reg memReg, uint64_t memOffset, Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                               = 0;
    virtual EncodeResult encodeCmpMemImm(Cpu::Reg memReg, uint64_t memOffset, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                             = 0;
    virtual EncodeResult encodeCmpRegImm(Cpu::Reg reg, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                                                    = 0;
    virtual EncodeResult encodeSetCondReg(Cpu::Reg reg, Cpu::Cond cpuCond, EmitFlags emitFlags)                                                                                                                    = 0;
    virtual EncodeResult encodeLoadCondRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::Cond setType, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                        = 0;
    virtual EncodeResult encodeClearReg(Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                                                                     = 0;
    virtual EncodeResult encodeOpUnaryMem(Cpu::Reg memReg, uint64_t memOffset, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                                = 0;
    virtual EncodeResult encodeOpUnaryReg(Cpu::Reg reg, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                                                       = 0;
    virtual EncodeResult encodeOpBinaryRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                               = 0;
    virtual EncodeResult encodeOpBinaryRegMem(Cpu::Reg regDst, Cpu::Reg memReg, uint64_t memOffset, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)                                                           = 0;
    virtual EncodeResult encodeOpBinaryMemReg(Cpu::Reg memReg, uint64_t memOffset, Cpu::Reg reg, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)                                                              = 0;
    virtual EncodeResult encodeOpBinaryRegImm(Cpu::Reg reg, uint64_t value, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                                   = 0;
    virtual EncodeResult encodeOpBinaryMemImm(Cpu::Reg memReg, uint64_t memOffset, uint64_t value, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)                                                            = 0;
    virtual EncodeResult encodeOpTernaryRegRegReg(Cpu::Reg reg0, Cpu::Reg reg1, Cpu::Reg reg2, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)                                                                = 0;

    void emitLoadSymRelocAddress(Cpu::Reg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags = EMIT_ZERO);
    void emitJumpReg(Cpu::Reg reg, EmitFlags emitFlags = EMIT_ZERO);
    void emitOpBinaryRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags = EMIT_ZERO);
    void emitOpBinaryRegImm(Cpu::Reg reg, uint64_t value, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags = EMIT_ZERO);
    void emitLoadRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits opBits, EmitFlags emitFlags = EMIT_ZERO);
    void emitLoadRegImm(Cpu::Reg reg, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags = EMIT_ZERO);
    void emitLoadSignedExtendRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags = EMIT_ZERO);
    void emitLoadZeroExtendRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags = EMIT_ZERO);
    void emitClearReg(Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags = EMIT_ZERO);

    Cpu::Symbol* getOrAddSymbol(IdentifierRef name, Cpu::SymbolKind kind);
    static void  addSymbolRelocation(uint32_t, uint32_t, uint16_t);

    Store                    store_;
    uint32_t                 textSectionOffset_ = 0;
    uint32_t                 symCsIndex_        = 0;
    BuildParameters          buildParams_;
    Cpu::Function*           cpuFct_ = nullptr;
    TaskContext*             ctx_    = nullptr;
    std::vector<Cpu::Symbol> symbols_;
};

SWC_END_NAMESPACE();
