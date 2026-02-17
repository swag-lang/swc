#pragma once
#include "Backend/CodeGen/Encoder/Encoder.h"
#include "Backend/CodeGen/Micro/MicroInstr.h"
#include "Backend/CodeGen/Micro/MicroPrinter.h"
#include "Backend/CodeGen/Micro/MicroStorage.h"
#include "Backend/Runtime.h"
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Support/Core/SmallVector.h"

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

struct MicroDebugInfo
{
    SourceCodeRef sourceCodeRef = SourceCodeRef::invalid();

    bool hasData() const
    {
        return sourceCodeRef.isValid();
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
    void                                addVirtualRegForbiddenPhysReg(MicroReg virtualReg, MicroReg forbiddenReg);
    void                                addVirtualRegForbiddenPhysRegs(MicroReg virtualReg, std::span<const MicroReg> forbiddenRegs);
    bool                                isVirtualRegPhysRegForbidden(MicroReg virtualReg, MicroReg physReg) const;
    bool                                isVirtualRegPhysRegForbidden(uint32_t virtualRegKey, MicroReg physReg) const;

    void runPasses(const MicroPassManager& passes, Encoder* encoder, MicroPassContext& context);

    void encodePush(MicroReg reg);
    void encodePop(MicroReg reg);
    void encodeNop();
    Ref  createLabel();
    void placeLabel(Ref labelRef);
    void encodeLabel(Ref& outLabelRef);
    void encodeRet();
    void encodeCallLocal(Symbol* targetSymbol, CallConvKind callConv);
    void encodeCallExtern(Symbol* targetSymbol, CallConvKind callConv);
    void encodeCallReg(MicroReg reg, CallConvKind callConv);
    void encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries);
    void encodeJumpToLabel(MicroCond cpuCond, MicroOpBits opBits, Ref labelRef);
    void encodeJumpReg(MicroReg reg);
    void encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits);
    void encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits);
    void encodeLoadRegPtrImm(MicroReg reg, uint64_t value, ConstantRef constantRef = ConstantRef::invalid(), Symbol* targetSymbol = nullptr);
    void encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits);
    void encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc);
    void encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc);
    void encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc);
    void encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc);
    void encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits);
    void encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc);
    void encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc);
    void encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue);
    void encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue);
    void encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits);
    void encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits);
    void encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits);
    void encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits);
    void encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits);
    void encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits);
    void encodeSetCondReg(MicroReg reg, MicroCond cpuCond);
    void encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits);
    void encodeClearReg(MicroReg reg, MicroOpBits opBits);
    void encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits);
    void encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits);
    void encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits);
    void encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits);
    void encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits);
    void encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits);
    void encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits);
    void encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits);

private:
    std::pair<Ref, MicroInstr&> addInstructionWithRef(MicroInstrOpcode op, uint8_t numOperands);
    MicroInstr&                 addInstruction(MicroInstrOpcode op, uint8_t numOperands);
    void                        storeInstructionDebugInfo(Ref instructionRef);

    TaskContext*                                        ctx_ = nullptr;
    MicroStorage                                        instructions_;
    MicroOperandStorage                                 operands_;
    MicroBuilderFlags                                   flags_ = MicroBuilderFlagsE::Zero;
    std::vector<std::optional<MicroDebugInfo>>          debugInfos_;
    MicroDebugInfo                                      currentDebugInfo_;
    Utf8                                                printSymbolName_;
    Utf8                                                printFilePath_;
    uint32_t                                            printSourceLine_ = 0;
    std::vector<Utf8>                                   printPassOptions_;
    Runtime::BuildCfgBackendOptim                       backendOptimizeLevel_ = Runtime::BuildCfgBackendOptim::O0;
    std::vector<Ref>                                    labels_;
    std::vector<MicroRelocation>                        codeRelocations_;
    std::unordered_map<uint32_t, SmallVector<MicroReg>> virtualRegForbiddenPhysRegs_;
};

SWC_END_NAMESPACE();
