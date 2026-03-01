#pragma once
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/MicroPrinter.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Runtime.h"
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class Symbol;

enum class MicroBuilderFlagsE : uint8_t
{
    Zero      = 0,
    DebugInfo = 1 << 0,
};
using MicroBuilderFlags = EnumFlags<MicroBuilderFlagsE>;

struct MicroRelocation
{
    static constexpr uint64_t K_SELF_ADDRESS = std::numeric_limits<uint64_t>::max();

    enum class Kind : uint8_t
    {
        ForeignFunctionAddress,
        ConstantAddress,
        LocalFunctionAddress,
    };

    Kind          kind           = Kind::ConstantAddress;
    uint32_t      codeOffset     = 0;
    MicroInstrRef instructionRef = MicroInstrRef::invalid();
    uint64_t      targetAddress  = 0;
    Symbol*       targetSymbol   = nullptr;
    ConstantRef   constantRef    = ConstantRef::invalid();
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
    TaskContext&       ctx() { return *SWC_NOT_NULL(ctx_); }
    const TaskContext& ctx() const { return *SWC_NOT_NULL(ctx_); }

    MicroStorage&              instructions() { return instructions_; }
    const MicroStorage&        instructions() const { return instructions_; }
    MicroOperandStorage&       operands() { return operands_; }
    const MicroOperandStorage& operands() const { return operands_; }

    Utf8                                formatInstructions(MicroRegPrintMode regPrintMode = MicroRegPrintMode::Default, const Encoder* encoder = nullptr) const;
    void                                printInstructions(MicroRegPrintMode regPrintMode = MicroRegPrintMode::Default, const Encoder* encoder = nullptr) const;
    void                                setFlags(MicroBuilderFlags flags) { flags_ = flags; }
    MicroBuilderFlags                   flags() const { return flags_; }
    bool                                hasFlag(MicroBuilderFlagsE flag) const { return flags_.has(flag); }
    void                                setCurrentDebugSourceCodeRef(const SourceCodeRef& sourceCodeRef);
    SourceCodeRef                       instructionSourceCodeRef(MicroInstrRef instructionRef) const;
    void                                setPrintPassOptions(std::span<const Utf8> options) { printPassOptions_.assign(options.begin(), options.end()); }
    void                                setBackendBuildCfg(const Runtime::BuildCfgBackend& value) { backendBuildCfg_ = value; }
    const Runtime::BuildCfgBackend&     backendBuildCfg() const { return backendBuildCfg_; }
    void                                setPrintLocation(Utf8 symbolName, Utf8 filePath, uint32_t sourceLine);
    const Utf8&                         printSymbolName() const { return printSymbolName_; }
    const Utf8&                         printFilePath() const { return printFilePath_; }
    uint32_t                            printSourceLine() const { return printSourceLine_; }
    void                                clearRelocations() { relocations_.clear(); }
    void                                addRelocation(const MicroRelocation& relocation);
    bool                                invalidateRelocationForInstruction(MicroInstrRef instructionRef);
    bool                                pruneDeadRelocations();
    std::vector<MicroRelocation>&       codeRelocations() { return relocations_; }
    const std::vector<MicroRelocation>& codeRelocations() const { return relocations_; }
    void                                addVirtualRegForbiddenPhysReg(MicroReg virtualReg, MicroReg forbiddenReg);
    void                                addVirtualRegForbiddenPhysRegs(MicroReg virtualReg, MicroRegSpan forbiddenRegs);
    bool                                isVirtualRegPhysRegForbidden(MicroReg virtualReg, MicroReg physReg) const;
    bool                                isVirtualRegPhysRegForbidden(uint32_t virtualRegKey, MicroReg physReg) const;
    uint32_t                            nextVirtualIntRegIndexHint() const;
    const MicroControlFlowGraph&        controlFlowGraph();
    void                                invalidateControlFlowGraph();
    void                                markControlFlowGraphMaybeDirty();

    MicroPassManager&       passManager() { return passManager_; }
    const MicroPassManager& passManager() const { return passManager_; }
    Result                  runPasses(Encoder* encoder, MicroPassContext& context);
    Result                  runPasses(const MicroPassManager& passes, Encoder* encoder, MicroPassContext& context);

    MicroLabelRef createLabel();
    void          placeLabel(MicroLabelRef labelRef);

    void emitPush(MicroReg reg);
    void emitPop(MicroReg reg);
    void emitNop();
    void emitBreakpoint();
    void emitAssertTrap();
    void emitLabel(MicroLabelRef& outLabelRef);
    void emitRet();
    void emitCallLocal(Symbol* targetSymbol, CallConvKind callConv);
    void emitCallExtern(Symbol* targetSymbol, CallConvKind callConv);
    void emitCallReg(MicroReg reg, CallConvKind callConv);
    void emitJumpToLabel(MicroCond cpuCond, MicroOpBits opBits, MicroLabelRef labelRef);
    void emitJumpReg(MicroReg reg);
    void emitLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits);
    void emitLoadRegImm(MicroReg reg, const ApInt& value, MicroOpBits opBits);
    void emitLoadRegPtrImm(MicroReg reg, uint64_t value);
    void emitLoadRegPtrReloc(MicroReg reg, uint64_t value, ConstantRef constantRef = ConstantRef::invalid(), Symbol* targetSymbol = nullptr);
    void emitLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits);
    void emitLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc);
    void emitLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc);
    void emitLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc);
    void emitLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc);
    void emitLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits);
    void emitLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc);
    void emitLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc);
    void emitLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, const ApInt& value, MicroOpBits opBitsValue);
    void emitLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue);
    void emitLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits);
    void emitLoadMemImm(MicroReg memReg, uint64_t memOffset, const ApInt& value, MicroOpBits opBits);
    void emitCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits);
    void emitCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits);
    void emitCmpMemImm(MicroReg memReg, uint64_t memOffset, const ApInt& value, MicroOpBits opBits);
    void emitCmpRegImm(MicroReg reg, const ApInt& value, MicroOpBits opBits);
    void emitSetCondReg(MicroReg reg, MicroCond cpuCond);
    void emitLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits);
    void emitClearReg(MicroReg reg, MicroOpBits opBits);
    void emitOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits);
    void emitOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits);
    void emitOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits);
    void emitOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits);
    void emitOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits);
    void emitOpBinaryRegImm(MicroReg reg, const ApInt& value, MicroOp op, MicroOpBits opBits);
    void emitOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, const ApInt& value, MicroOp op, MicroOpBits opBits);
    void emitOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits);

private:
    std::pair<MicroInstrRef, MicroInstr&> addInstructionWithRef(MicroInstrOpcode op, uint8_t numOperands);
    MicroInstr&                           addInstruction(MicroInstrOpcode op, uint8_t numOperands);
    void                                  storeInstructionDebugInfo(MicroInstrRef instructionRef);

    TaskContext*                                        ctx_ = nullptr;
    MicroStorage                                        instructions_;
    MicroOperandStorage                                 operands_;
    MicroBuilderFlags                                   flags_                     = MicroBuilderFlagsE::Zero;
    SourceCodeRef                                       currentDebugSourceCodeRef_ = SourceCodeRef::invalid();
    Utf8                                                printSymbolName_;
    Utf8                                                printFilePath_;
    uint32_t                                            printSourceLine_ = 0;
    std::vector<Utf8>                                   printPassOptions_;
    Runtime::BuildCfgBackend                            backendBuildCfg_{};
    std::vector<MicroInstrRef>                          labels_;
    std::vector<MicroRelocation>                        relocations_;
    std::unordered_map<uint32_t, SmallVector<MicroReg>> virtualRegForbiddenPhysRegs_;
    MicroPassManager                                    passManager_;
    MicroControlFlowGraph                               controlFlowGraph_;
    uint64_t                                            controlFlowGraphStorageRevision_ = 0;
    uint64_t                                            controlFlowGraphHash_            = 0;
    bool                                                hasControlFlowGraph_             = false;
    bool                                                controlFlowGraphMaybeDirty_      = false;
};

SWC_END_NAMESPACE();
