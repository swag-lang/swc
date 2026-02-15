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

    EncodeResult encodeLoadSymbolRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EncodeFlags emitFlags);
    EncodeResult encodeLoadSymRelocValue(MicroReg reg, uint32_t symbolIndex, uint32_t offset, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodePush(MicroReg reg, EncodeFlags emitFlags);
    EncodeResult encodePop(MicroReg reg, EncodeFlags emitFlags);
    EncodeResult encodeNop(EncodeFlags emitFlags);
    Ref          createLabel();
    EncodeResult placeLabel(Ref labelRef, EncodeFlags emitFlags);
    EncodeResult encodeLabel(Ref& outLabelRef, EncodeFlags emitFlags);
    EncodeResult encodeRet(EncodeFlags emitFlags);
    EncodeResult encodeCallLocal(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags);
    EncodeResult encodeCallExtern(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags);
    EncodeResult encodeCallReg(MicroReg reg, CallConvKind callConv, EncodeFlags emitFlags);
    EncodeResult encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EncodeFlags emitFlags);
    EncodeResult encodeJumpToLabel(MicroCondJump jumpType, MicroOpBits opBits, Ref labelRef, EncodeFlags emitFlags);
    EncodeResult encodeJump(MicroJump& jump, MicroCondJump jumpType, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodePatchJump(const MicroJump& jump, uint64_t offsetDestination, EncodeFlags emitFlags);
    EncodeResult encodePatchJump(const MicroJump& jump, EncodeFlags emitFlags);
    EncodeResult encodePatchJumpToInstruction(const MicroJump& jump, Ref instructionRef, EncodeFlags emitFlags);
    EncodeResult encodeJumpReg(MicroReg reg, EncodeFlags emitFlags);
    EncodeResult encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags);
    EncodeResult encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags);
    EncodeResult encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags);
    EncodeResult encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags);
    EncodeResult encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc, EncodeFlags emitFlags);
    EncodeResult encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc, EncodeFlags emitFlags);
    EncodeResult encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EncodeFlags emitFlags);
    EncodeResult encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue, EncodeFlags emitFlags);
    EncodeResult encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeSetCondReg(MicroReg reg, MicroCond cpuCond, EncodeFlags emitFlags);
    EncodeResult encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeClearReg(MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);

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
