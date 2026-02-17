#pragma once
#include "Backend/CodeGen/Encoder/Encoder.h"
#include "Backend/CodeGen/Micro/MicroInstr.h"
#include "Backend/CodeGen/Micro/MicroPrinter.h"
#include "Backend/CodeGen/Micro/MicroStorage.h"
#include "Backend/Runtime.h"
#include "Compiler/Lexer/SourceCodeRange.h"

SWC_BEGIN_NAMESPACE();

class MicroPassManager;
struct MicroPassContext;
class Symbol;

enum class MicroBuilderFlagsE : uint8_t
{
    Zero      = 0,
    DebugInfo = 1 << 0,
};
using MicroBuilderFlags = EnumFlags<MicroBuilderFlagsE>;

enum class MicroDebugInfoPayloadKind : uint8_t
{
    None,
    Symbol,
};

struct MicroDebugInfo
{
    SourceCodeRef             sourceCodeRef = SourceCodeRef::invalid();
    MicroDebugInfoPayloadKind payloadKind   = MicroDebugInfoPayloadKind::None;
    union
    {
        Symbol*  symbol;
        uint64_t payloadU64;
    };

    MicroDebugInfo() :
        symbol(nullptr)
    {
    }

    void clearPayload()
    {
        payloadKind = MicroDebugInfoPayloadKind::None;
        symbol      = nullptr;
    }

    void setPayloadSymbol(Symbol* payloadSymbol)
    {
        payloadKind = MicroDebugInfoPayloadKind::Symbol;
        symbol      = payloadSymbol;
    }

    Symbol* payloadSymbol() const
    {
        return payloadKind == MicroDebugInfoPayloadKind::Symbol ? symbol : nullptr;
    }

    bool hasData() const
    {
        return sourceCodeRef.isValid() || payloadSymbol() != nullptr;
    }
};

struct MicroRelocation
{
    static constexpr uint64_t K_SELF_ADDRESS = std::numeric_limits<uint64_t>::max();

    enum class Kind : uint8_t
    {
        ForeignFunctionAddress,
        ConstantAddress,
        LocalFunctionAddress,
    };

    Kind        kind           = Kind::ConstantAddress;
    uint32_t    codeOffset     = 0;
    Ref         instructionRef = INVALID_REF;
    uint64_t    targetAddress  = 0;
    Symbol*     targetSymbol   = nullptr;
    ConstantRef constantRef    = ConstantRef::invalid();
};

class MicroBuilder
{
public:
    MicroBuilder() = default;

    explicit MicroBuilder(TaskContext& ctx) :
        ctx_(&ctx)
    {
    }

    MicroBuilder(const MicroBuilder&)                = delete;
    MicroBuilder& operator=(const MicroBuilder&)     = delete;
    MicroBuilder(MicroBuilder&&) noexcept            = default;
    MicroBuilder& operator=(MicroBuilder&&) noexcept = default;

    void               setContext(TaskContext& ctx) { ctx_ = &ctx; }
    TaskContext&       ctx() { return *SWC_CHECK_NOT_NULL(ctx_); }
    const TaskContext& ctx() const { return *SWC_CHECK_NOT_NULL(ctx_); }

    MicroStorage&              instructions() { return instructions_; }
    const MicroStorage&        instructions() const { return instructions_; }
    MicroOperandStorage&       operands() { return operands_; }
    const MicroOperandStorage& operands() const { return operands_; }

    Utf8                                formatInstructions(MicroRegPrintMode regPrintMode = MicroRegPrintMode::Default, const Encoder* encoder = nullptr) const;
    void                                printInstructions(MicroRegPrintMode regPrintMode = MicroRegPrintMode::Default, const Encoder* encoder = nullptr) const;
    void                                setFlags(MicroBuilderFlags flags) { flags_ = flags; }
    MicroBuilderFlags                   flags() const { return flags_; }
    bool                                hasFlag(MicroBuilderFlagsE flag) const { return flags_.has(flag); }
    void                                setCurrentDebugInfo(const MicroDebugInfo& debugInfo) { currentDebugInfo_ = debugInfo; }
    const MicroDebugInfo&               currentDebugInfo() const { return currentDebugInfo_; }
    void                                setCurrentDebugSourceCodeRef(const SourceCodeRef& sourceCodeRef) { currentDebugInfo_.sourceCodeRef = sourceCodeRef; }
    void                                setCurrentDebugSymbol(Symbol* symbol) { currentDebugInfo_.setPayloadSymbol(symbol); }
    void                                clearCurrentDebugPayload() { currentDebugInfo_.clearPayload(); }
    const MicroDebugInfo*               debugInfo(Ref instructionRef) const;
    void                                setPrintPassOptions(std::span<const Utf8> options) { printPassOptions_.assign(options.begin(), options.end()); }
    void                                setBackendOptimizeLevel(Runtime::BuildCfgBackendOptim value) { backendOptimizeLevel_ = value; }
    Runtime::BuildCfgBackendOptim       backendOptimizeLevel() const { return backendOptimizeLevel_; }
    void                                setPrintLocation(Utf8 symbolName, Utf8 filePath, uint32_t sourceLine);
    const Utf8&                         printSymbolName() const { return printSymbolName_; }
    const Utf8&                         printFilePath() const { return printFilePath_; }
    uint32_t                            printSourceLine() const { return printSourceLine_; }
    void                                clearRelocations() { codeRelocations_.clear(); }
    void                                addRelocation(const MicroRelocation& relocation);
    std::vector<MicroRelocation>&       codeRelocations() { return codeRelocations_; }
    const std::vector<MicroRelocation>& codeRelocations() const { return codeRelocations_; }

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
    void encodeCallLocal(Symbol* targetSymbol, CallConvKind callConv, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeCallExtern(Symbol* targetSymbol, CallConvKind callConv, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeCallReg(MicroReg reg, CallConvKind callConv, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeJumpToLabel(MicroCond cpuCond, MicroOpBits opBits, Ref labelRef, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeJumpReg(MicroReg reg, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags = EncodeFlagsE::Zero);
    void encodeLoadRegPtrImm(MicroReg reg, uint64_t value, ConstantRef constantRef = ConstantRef::invalid(), Symbol* targetSymbol = nullptr, EncodeFlags emitFlags = EncodeFlagsE::Zero);
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

    TaskContext*                               ctx_ = nullptr;
    MicroStorage                               instructions_;
    MicroOperandStorage                        operands_;
    MicroBuilderFlags                          flags_ = MicroBuilderFlagsE::Zero;
    std::vector<std::optional<MicroDebugInfo>> debugInfos_;
    MicroDebugInfo                             currentDebugInfo_;
    Utf8                                       printSymbolName_;
    Utf8                                       printFilePath_;
    uint32_t                                   printSourceLine_ = 0;
    std::vector<Utf8>                          printPassOptions_;
    Runtime::BuildCfgBackendOptim              backendOptimizeLevel_ = Runtime::BuildCfgBackendOptim::O0;
    std::vector<Ref>                           labels_;
    std::vector<MicroRelocation>               codeRelocations_;
};

SWC_END_NAMESPACE();
