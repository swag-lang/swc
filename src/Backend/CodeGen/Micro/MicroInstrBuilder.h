#pragma once
#include "Backend/CodeGen/Encoder/Encoder.h"
#include "Backend/CodeGen/Micro/MicroInstr.h"
#include "Backend/CodeGen/Micro/MicroInstrPrinter.h"
#include "Backend/CodeGen/Micro/MicroInstrStorage.h"
#include "Compiler/Lexer/SourceCodeRange.h"

SWC_BEGIN_NAMESPACE();

class MicroPassManager;
struct MicroPassContext;

enum class MicroInstrBuilderFlagsE : uint8_t
{
    Zero              = 0,
    PrintBeforePasses = 1 << 0,
    PrintBeforeEncode = 1 << 1,
    DebugInfo         = 1 << 2,
};
using MicroInstrBuilderFlags = EnumFlags<MicroInstrBuilderFlagsE>;

struct MicroInstrDebugInfo
{
    SourceCodeRef sourceCodeRef = SourceCodeRef::invalid();

    bool hasData() const
    {
        return sourceCodeRef.isValid();
    }
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

    std::string                formatInstructions(MicroInstrRegPrintMode regPrintMode = MicroInstrRegPrintMode::Default, const Encoder* encoder = nullptr, bool colorize = false) const;
    void                       printInstructions(MicroInstrRegPrintMode regPrintMode = MicroInstrRegPrintMode::Default, const Encoder* encoder = nullptr, bool colorize = true) const;
    void                       setFlags(MicroInstrBuilderFlags flags) { flags_ = flags; }
    MicroInstrBuilderFlags     flags() const { return flags_; }
    bool                       hasFlag(MicroInstrBuilderFlagsE flag) const { return flags_.has(flag); }
    void                       setCurrentDebugInfo(const MicroInstrDebugInfo& debugInfo) { currentDebugInfo_ = debugInfo; }
    void                       setCurrentDebugSourceCodeRef(const SourceCodeRef& sourceCodeRef) { currentDebugInfo_.sourceCodeRef = sourceCodeRef; }
    const MicroInstrDebugInfo* debugInfo(Ref instructionRef) const;
    void                       setPrintLocation(std::string symbolName, std::string filePath, uint32_t sourceLine);
    const std::string&         printSymbolName() const { return printSymbolName_; }
    const std::string&         printFilePath() const { return printFilePath_; }
    uint32_t                   printSourceLine() const { return printSourceLine_; }

    void runPasses(const MicroPassManager& passes, Encoder* encoder, MicroPassContext& context);

    void encodeLoadSymbolRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EncodeFlags emitFlags);
    void encodeLoadSymRelocValue(MicroReg reg, uint32_t symbolIndex, uint32_t offset, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodePush(MicroReg reg, EncodeFlags emitFlags);
    void encodePop(MicroReg reg, EncodeFlags emitFlags);
    void encodeNop(EncodeFlags emitFlags);
    Ref          createLabel();
    void placeLabel(Ref labelRef, EncodeFlags emitFlags);
    void encodeLabel(Ref& outLabelRef, EncodeFlags emitFlags);
    void encodeRet(EncodeFlags emitFlags);
    void encodeCallLocal(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags);
    void encodeCallExtern(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags);
    void encodeCallReg(MicroReg reg, CallConvKind callConv, EncodeFlags emitFlags);
    void encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EncodeFlags emitFlags);
    void encodeJumpToLabel(MicroCond cpuCond, MicroOpBits opBits, Ref labelRef, EncodeFlags emitFlags);
    void encodeJumpReg(MicroReg reg, EncodeFlags emitFlags);
    void encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags);
    void encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags);
    void encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags);
    void encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags);
    void encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc, EncodeFlags emitFlags);
    void encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc, EncodeFlags emitFlags);
    void encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EncodeFlags emitFlags);
    void encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue, EncodeFlags emitFlags);
    void encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeSetCondReg(MicroReg reg, MicroCond cpuCond, EncodeFlags emitFlags);
    void encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeClearReg(MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    void encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);

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
    std::string                                     printSymbolName_;
    std::string                                     printFilePath_;
    uint32_t                                        printSourceLine_ = 0;
    std::vector<Ref>                                labels_;
};

SWC_END_NAMESPACE();

