#pragma once
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Backend/CodeGen/Encoder/EncoderTypes.h"
#include "Backend/CodeGen/Micro/MicroReg.h"
#include "Backend/CodeGen/Micro/MicroTypes.h"
#include "Support/Core/PagedStore.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
struct MicroInstr;
struct MicroInstrOperand;
struct MicroInstrUseDef;
class MicroEncodePass;
class MicroLegalizePass;

enum class EncodeFlagsE : uint8_t
{
    Zero      = 0,
    Overflow  = 1 << 0,
    Lock      = 1 << 1,
    B64       = 1 << 2,
};
using EncodeFlags = EnumFlags<EncodeFlagsE>;

enum class MicroConformanceIssueKind : uint8_t
{
    None,
    ClampImmediate,
    NormalizeOpBits,
    SplitLoadMemImm64,
    SplitLoadAmcMemImm64,
    RewriteLoadFloatRegImm,
};

struct MicroConformanceIssue
{
    MicroConformanceIssueKind kind            = MicroConformanceIssueKind::None;
    uint8_t                   operandIndex    = 0;
    uint64_t                  valueLimitU64   = 0;
    MicroOpBits               normalizedOpBits = MicroOpBits::Zero;
};

class Encoder
{
    friend class MicroInstrBuilder;
    friend class MicroEncodePass;
    friend class MicroLegalizePass;
    friend struct MicroInstr;

public:
    uint32_t            size() const { return store_.size(); }
    const uint8_t*      data() const;
    uint8_t             byteAt(uint32_t index) const;
    void                copyTo(std::span<std::byte> dst) const;
    virtual std::string formatRegisterName(MicroReg reg) const;
    virtual MicroReg    stackPointerReg() const = 0;

protected:
    TaskContext&       ctx() { return *SWC_CHECK_NOT_NULL(ctx_); }
    const TaskContext& ctx() const { return *SWC_CHECK_NOT_NULL(ctx_); }

    explicit Encoder(TaskContext& ctx);
    virtual ~Encoder()                     = default;
    virtual uint64_t currentOffset() const = 0;

    virtual void encodeLoadSymbolRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EncodeFlags emitFlags)                                                                                    = 0;
    virtual void encodeLoadSymRelocValue(MicroReg reg, uint32_t symbolIndex, uint32_t offset, MicroOpBits opBits, EncodeFlags emitFlags)                                                                     = 0;
    virtual void encodePush(MicroReg reg, EncodeFlags emitFlags)                                                                                                                                             = 0;
    virtual void encodePop(MicroReg reg, EncodeFlags emitFlags)                                                                                                                                              = 0;
    virtual void encodeNop(EncodeFlags emitFlags)                                                                                                                                                            = 0;
    virtual void encodeRet(EncodeFlags emitFlags)                                                                                                                                                            = 0;
    virtual void encodeCallLocal(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags)                                                                                                     = 0;
    virtual void encodeCallExtern(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags)                                                                                                    = 0;
    virtual void encodeCallReg(MicroReg reg, CallConvKind callConv, EncodeFlags emitFlags)                                                                                                                   = 0;
    virtual void encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EncodeFlags emitFlags)                                                 = 0;
    virtual void encodeJump(MicroJump& jump, MicroCond cpuCond, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                                  = 0;
    virtual void encodePatchJump(const MicroJump& jump, uint64_t offsetDestination, EncodeFlags emitFlags)                                                                                                   = 0;
    virtual void encodePatchJump(const MicroJump& jump, EncodeFlags emitFlags)                                                                                                                               = 0;
    virtual void encodeJumpReg(MicroReg reg, EncodeFlags emitFlags)                                                                                                                                          = 0;
    virtual void encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags)                                                                              = 0;
    virtual void encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                                   = 0;
    virtual void encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                               = 0;
    virtual void encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)                                      = 0;
    virtual void encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)                                                       = 0;
    virtual void encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)                                        = 0;
    virtual void encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)                                                         = 0;
    virtual void encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags)                                                                       = 0;
    virtual void encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc, EncodeFlags emitFlags)          = 0;
    virtual void encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc, EncodeFlags emitFlags)      = 0;
    virtual void encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EncodeFlags emitFlags)     = 0;
    virtual void encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue, EncodeFlags emitFlags) = 0;
    virtual void encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)                                                                              = 0;
    virtual void encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)                                                                            = 0;
    virtual void encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                                    = 0;
    virtual void encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)                                                                               = 0;
    virtual void encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)                                                                             = 0;
    virtual void encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                                    = 0;
    virtual void encodeSetCondReg(MicroReg reg, MicroCond cpuCond, EncodeFlags emitFlags)                                                                                                                    = 0;
    virtual void encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits, EncodeFlags emitFlags)                                                                        = 0;
    virtual void encodeClearReg(MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                                                     = 0;
    virtual void encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                = 0;
    virtual void encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                                       = 0;
    virtual void encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)                                                                               = 0;
    virtual void encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)                                                           = 0;
    virtual void encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)                                                              = 0;
    virtual void encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)                                                                                   = 0;
    virtual void encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)                                                            = 0;
    virtual void encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)                                                                = 0;

    virtual void updateRegUseDef(const MicroInstr&, const MicroInstrOperand*, MicroInstrUseDef&) const {}
    virtual bool queryConformanceIssue(MicroConformanceIssue& outIssue, const MicroInstr&, const MicroInstrOperand*) const { return false; }

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


