#pragma once
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Encoder/EncoderTypes.h"
#include "Backend/MachineCode/Micro/MicroReg.h"
#include "Backend/MachineCode/Micro/MicroTypes.h"
#include "Support/Core/PagedStore.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
struct MicroInstr;
struct MicroInstrOperand;
struct MicroInstrUseDef;
class MicroEncodePass;

enum class EncodeFlagsE : uint8_t
{
    Zero      = 0,
    Overflow  = 1 << 0,
    Lock      = 1 << 1,
    B64       = 1 << 2,
    CanEncode = 1 << 3,
};
using EncodeFlags = EnumFlags<EncodeFlagsE>;

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
    friend class MicroInstrBuilder;
    friend class MicroEncodePass;
    friend struct MicroInstr;

public:
    uint32_t            size() const { return store_.size(); }
    const uint8_t*      data() const;
    uint8_t             byteAt(uint32_t index) const;
    void                copyTo(std::span<std::byte> dst) const;
    virtual std::string formatRegisterName(MicroReg reg) const;

protected:
    TaskContext&       ctx() { return *ctx_; }
    const TaskContext& ctx() const { return *ctx_; }

    explicit Encoder(TaskContext& ctx);
    virtual ~Encoder() = default;

    virtual EncodeResult encodeLoadSymbolRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EncodeFlags emitFlags)                                                                                    = 0;
    virtual EncodeResult encodeLoadSymRelocValue(MicroReg reg, uint32_t symbolIndex, uint32_t offset, MicroOpBits opBits, EncodeFlags emitFlags)                                                                     = 0;
    virtual EncodeResult encodePush(MicroReg reg, EncodeFlags emitFlags)                                                                                                                                             = 0;
    virtual EncodeResult encodePop(MicroReg reg, EncodeFlags emitFlags)                                                                                                                                              = 0;
    virtual EncodeResult encodeNop(EncodeFlags emitFlags)                                                                                                                                                            = 0;
    virtual EncodeResult encodeRet(EncodeFlags emitFlags)                                                                                                                                                            = 0;
    virtual EncodeResult encodeCallLocal(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags)                                                                                                     = 0;
    virtual EncodeResult encodeCallExtern(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags)                                                                                                    = 0;
    virtual EncodeResult encodeCallReg(MicroReg reg, CallConvKind callConv, EncodeFlags emitFlags)                                                                                                                   = 0;
    virtual EncodeResult encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EncodeFlags emitFlags)                                                 = 0;
    virtual EncodeResult encodeJump(MicroJump& jump, MicroCondJump jumpType, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                              = 0;
    virtual EncodeResult encodePatchJump(const MicroJump& jump, uint64_t offsetDestination, EncodeFlags emitFlags)                                                                                                   = 0;
    virtual EncodeResult encodePatchJump(const MicroJump& jump, EncodeFlags emitFlags)                                                                                                                               = 0;
    virtual EncodeResult encodeJumpReg(MicroReg reg, EncodeFlags emitFlags)                                                                                                                                          = 0;
    virtual EncodeResult encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags)                                                                              = 0;
    virtual EncodeResult encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                                   = 0;
    virtual EncodeResult encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                               = 0;
    virtual EncodeResult encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)                                      = 0;
    virtual EncodeResult encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)                                                       = 0;
    virtual EncodeResult encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)                                        = 0;
    virtual EncodeResult encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)                                                         = 0;
    virtual EncodeResult encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags)                                                                       = 0;
    virtual EncodeResult encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc, EncodeFlags emitFlags)          = 0;
    virtual EncodeResult encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc, EncodeFlags emitFlags)      = 0;
    virtual EncodeResult encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EncodeFlags emitFlags)     = 0;
    virtual EncodeResult encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue, EncodeFlags emitFlags) = 0;
    virtual EncodeResult encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)                                                                              = 0;
    virtual EncodeResult encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)                                                                            = 0;
    virtual EncodeResult encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                                    = 0;
    virtual EncodeResult encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)                                                                               = 0;
    virtual EncodeResult encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)                                                                             = 0;
    virtual EncodeResult encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                                    = 0;
    virtual EncodeResult encodeSetCondReg(MicroReg reg, MicroCond cpuCond, EncodeFlags emitFlags)                                                                                                                    = 0;
    virtual EncodeResult encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits, EncodeFlags emitFlags)                                                                        = 0;
    virtual EncodeResult encodeClearReg(MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                                                     = 0;
    virtual EncodeResult encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                = 0;
    virtual EncodeResult encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                                       = 0;
    virtual EncodeResult encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)                                                                               = 0;
    virtual EncodeResult encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)                                                           = 0;
    virtual EncodeResult encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)                                                              = 0;
    virtual EncodeResult encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                   = 0;
    virtual EncodeResult encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)                                                            = 0;
    virtual EncodeResult encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)                                                                = 0;

    virtual void updateRegUseDef(const MicroInstr&, const MicroInstrOperand*, MicroInstrUseDef&) const {}

    EncoderSymbol* getOrAddSymbol(IdentifierRef name, EncoderSymbolKind kind);
    static void    addSymbolRelocation(uint32_t, uint32_t, uint16_t);

    TaskContext*               ctx_ = nullptr;
    PagedStore                 store_;
    uint32_t                   textSectionOffset_ = 0;
    uint32_t                   symCsIndex_        = 0;
    EncoderFunction*           cpuFct_            = nullptr;
    std::vector<EncoderSymbol> symbols_;
};

SWC_END_NAMESPACE();
