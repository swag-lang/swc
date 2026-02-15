#pragma once
#include "Backend/CodeGen/Encoder/Encoder.h"
#include "Backend/CodeGen/Micro/MicroInstr.h"
#include "Backend/CodeGen/Micro/MicroInstrPrinter.h"
#include "Backend/CodeGen/Micro/MicroInstrStorage.h"
#include "Compiler/Lexer/SourceCodeRange.h"

SWC_BEGIN_NAMESPACE();

class MicroPassManager;
struct MicroPassContext;
class Symbol;

enum class MicroInstrBuilderFlagsE : uint8_t
{
    Zero      = 0,
    DebugInfo = 1 << 0,
};
using MicroInstrBuilderFlags = EnumFlags<MicroInstrBuilderFlagsE>;

enum class MicroInstrDebugInfoPayloadKind : uint8_t
{
    None,
    Symbol,
};

struct MicroInstrDebugInfo
{
    SourceCodeRef sourceCodeRef = SourceCodeRef::invalid();
    MicroInstrDebugInfoPayloadKind payloadKind = MicroInstrDebugInfoPayloadKind::None;
    union
    {
        Symbol*  symbol;
        uint64_t payloadU64;
    };

    MicroInstrDebugInfo() :
        symbol(nullptr)
    {
    }

    void clearPayload()
    {
        payloadKind = MicroInstrDebugInfoPayloadKind::None;
        symbol      = nullptr;
    }

    void setPayloadSymbol(Symbol* payloadSymbol)
    {
        payloadKind = MicroInstrDebugInfoPayloadKind::Symbol;
        symbol      = payloadSymbol;
    }

    Symbol* payloadSymbol() const
    {
        return payloadKind == MicroInstrDebugInfoPayloadKind::Symbol ? symbol : nullptr;
    }

    bool hasData() const
    {
        return sourceCodeRef.isValid() || payloadSymbol() != nullptr;
    }
};

struct MicroInstrCodeRelocation
{
    enum class Kind : uint8_t
    {
        Rel32,
    };

    Kind          kind          = Kind::Rel32;
    uint32_t      codeOffset    = 0;
    IdentifierRef symbolName    = IdentifierRef::invalid();
    uint64_t      targetAddress = 0;
};

class MicroInstrBuilder
{
public:
    MicroInstrBuilder() = default;

    explicit MicroInstrBuilder(TaskContext& ctx) :
        ctx_(&ctx)
    {
    }

    MicroInstrBuilder(const MicroInstrBuilder&)                = delete;
    MicroInstrBuilder& operator=(const MicroInstrBuilder&)     = delete;
    MicroInstrBuilder(MicroInstrBuilder&&) noexcept            = default;
    MicroInstrBuilder& operator=(MicroInstrBuilder&&) noexcept = default;

    void               setContext(TaskContext& ctx) { ctx_ = &ctx; }
    TaskContext&       ctx() { return *SWC_CHECK_NOT_NULL(ctx_); }
    const TaskContext& ctx() const { return *SWC_CHECK_NOT_NULL(ctx_); }

    MicroInstrStorage&         instructions() { return instructions_; }
    const MicroInstrStorage&   instructions() const { return instructions_; }
    MicroOperandStorage&       operands() { return operands_; }
    const MicroOperandStorage& operands() const { return operands_; }

    Utf8                       formatInstructions(MicroInstrRegPrintMode regPrintMode = MicroInstrRegPrintMode::Default, const Encoder* encoder = nullptr, bool colorize = false) const;
    void                       printInstructions(MicroInstrRegPrintMode regPrintMode = MicroInstrRegPrintMode::Default, const Encoder* encoder = nullptr, bool colorize = true) const;
    void                       setFlags(MicroInstrBuilderFlags flags) { flags_ = flags; }
    MicroInstrBuilderFlags     flags() const { return flags_; }
    bool                       hasFlag(MicroInstrBuilderFlagsE flag) const { return flags_.has(flag); }
    void                       setCurrentDebugInfo(const MicroInstrDebugInfo& debugInfo) { currentDebugInfo_ = debugInfo; }
    const MicroInstrDebugInfo& currentDebugInfo() const { return currentDebugInfo_; }
    void                       setCurrentDebugSourceCodeRef(const SourceCodeRef& sourceCodeRef) { currentDebugInfo_.sourceCodeRef = sourceCodeRef; }
    void                       setCurrentDebugSymbol(Symbol* symbol) { currentDebugInfo_.setPayloadSymbol(symbol); }
    void                       clearCurrentDebugPayload() { currentDebugInfo_.clearPayload(); }
    const MicroInstrDebugInfo* debugInfo(Ref instructionRef) const;
    void                       setPrintPassOptions(std::span<const Utf8> options) { printPassOptions_.assign(options.begin(), options.end()); }
    void                       setPrintLocation(Utf8 symbolName, Utf8 filePath, uint32_t sourceLine);
    const Utf8&                printSymbolName() const { return printSymbolName_; }
    const Utf8&                printFilePath() const { return printFilePath_; }
    uint32_t                   printSourceLine() const { return printSourceLine_; }
    void                       clearCodeRelocations() { codeRelocations_.clear(); }
    void                       addCodeRelocation(MicroInstrCodeRelocation relocation);
    const std::vector<MicroInstrCodeRelocation>& codeRelocations() const { return codeRelocations_; }

    void runPasses(const MicroPassManager& passes, Encoder* encoder, MicroPassContext& context);

    void encodeLoadSymbolRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadSymRelocValue(MicroReg reg, uint32_t symbolIndex, uint32_t offset, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodePush(MicroReg reg, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodePop(MicroReg reg, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeNop(EncodeFlags emitFlags = EncodeFlagsE::Zero);
    Ref  createLabel();
    void placeLabel(Ref labelRef, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLabel(Ref& outLabelRef, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeRet(EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeCallLocal(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags = EncodeFlagsE::Zero, uint64_t targetAddress = 0);
    void encodeCallExtern(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeCallReg(MicroReg reg, CallConvKind callConv, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeJumpToLabel(MicroCond cpuCond, MicroOpBits opBits, Ref labelRef, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeJumpReg(MicroReg reg, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeSetCondReg(MicroReg reg, MicroCond cpuCond, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeClearReg(MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);

private:
    std::pair<Ref, MicroInstr&> addInstructionWithRef(MicroInstrOpcode op, EncodeFlags emitFlags, uint8_t numOperands);
    MicroInstr&                 addInstruction(MicroInstrOpcode op, EncodeFlags emitFlags, uint8_t numOperands);
    void                        storeInstructionDebugInfo(Ref instructionRef);

    TaskContext*                                    ctx_ = nullptr;
    MicroInstrStorage                               instructions_;
    MicroOperandStorage                             operands_;
    MicroInstrBuilderFlags                          flags_ = MicroInstrBuilderFlagsE::Zero;
    std::vector<std::optional<MicroInstrDebugInfo>> debugInfos_;
    MicroInstrDebugInfo                             currentDebugInfo_;
    Utf8                                            printSymbolName_;
    Utf8                                            printFilePath_;
    uint32_t                                        printSourceLine_ = 0;
    std::vector<Utf8>                               printPassOptions_;
    std::vector<Ref>                                labels_;
    std::vector<MicroInstrCodeRelocation>           codeRelocations_;
};

SWC_END_NAMESPACE();
