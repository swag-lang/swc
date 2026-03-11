#pragma once
#include "Backend/Micro/MicroPassManager.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

struct KnownConstant
{
    uint64_t value = 0;
};

struct KnownConstantPointer
{
    uint64_t    pointer     = 0;
    uint64_t    offset      = 0;
    ConstantRef constantRef = ConstantRef::invalid();
};

struct CompareState
{
    bool        valid  = false;
    uint64_t    lhs    = 0;
    uint64_t    rhs    = 0;
    MicroOpBits opBits = MicroOpBits::B64;
};

struct StackSlotKey
{
    uint64_t    offset = 0;
    MicroOpBits opBits = MicroOpBits::Zero;

    bool operator==(const StackSlotKey&) const = default;
};

struct StackSlotKeyHash
{
    size_t operator()(const StackSlotKey& key) const
    {
        size_t hash = std::hash<uint64_t>{}(key.offset);
        hash ^= std::hash<uint32_t>{}(static_cast<uint32_t>(key.opBits) + 0x9e3779b9u);
        return hash;
    }
};

using KnownRegMap             = std::unordered_map<MicroReg, KnownConstant>;
using KnownStackSlotMap       = std::unordered_map<StackSlotKey, KnownConstant, StackSlotKeyHash>;
using KnownAddressMap         = std::unordered_map<MicroReg, uint64_t>;
using KnownStackAddressMap    = std::unordered_map<uint64_t, uint64_t>;
using KnownConstantPointerMap = std::unordered_map<MicroReg, KnownConstantPointer>;

struct MicroRelocation;
class MicroStorage;
class MicroOperandStorage;
struct MicroInstrUseDef;
namespace Math
{
    enum class FoldStatus : uint8_t;
}

class MicroConstantPropagationPass final : public MicroPass
{
public:
    std::string_view name() const override { return "const-prop"; }
    Result           run(MicroPassContext& context) override;

private:
    using DeferredDef = std::optional<std::pair<MicroReg, uint64_t>>;
    enum class BinaryFoldResult : uint8_t
    {
        NotFolded,
        Folded,
        SafetyError,
    };

    struct InstrRewriteSnapshot
    {
        static constexpr uint32_t K_MAX_OPERANDS = 8;

        MicroInstrOpcode                              op          = MicroInstrOpcode::Nop;
        uint8_t                                       numOperands = 0;
        std::array<MicroInstrOperand, K_MAX_OPERANDS> operands{};
    };

    Result                  rewriteInstructionFromKnownValues(MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops, DeferredDef& deferredKnownDef, DeferredDef& deferredAddressDef);
    Result                  rewriteLoadFromMemoryInstructions(MicroInstr& inst, MicroInstrOperand* ops, DeferredDef& deferredKnownDef, DeferredDef& deferredAddressDef) const;
    Result                  rewriteLoadAndMoveInstructions(MicroInstr& inst, MicroInstrOperand* ops, DeferredDef& deferredAddressDef);
    Result                  rewriteRegisterOperationInstructions(MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops, DeferredDef& deferredKnownDef, DeferredDef& deferredAddressDef);
    Result                  rewriteMemoryOperandInstructions(MicroInstr& inst, MicroInstrOperand* ops);
    void                    invalidateStateForDefinitions(const MicroInstrUseDef& useDef);
    Result                  trackKnownMemoryWrite(MicroInstrRef instRef, const MicroInstr* prevInst, const MicroInstrOperand* prevOps, const MicroInstr& inst, const MicroInstrOperand* ops);
    Result                  trackStackStoreInstruction(const MicroInstr* prevInst, const MicroInstrOperand* prevOps, const MicroInstr& inst, const MicroInstrOperand* ops, bool& handledMemoryWrite);
    Result                  trackStackMutationInstruction(MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops, bool& handledMemoryWrite);
    bool                    tryTrackConstantPointerStackCopy(uint64_t stackOffset, MicroOpBits slotOpBits, MicroReg sourceReg, const MicroInstr* prevInst, const MicroInstrOperand* prevOps);
    Result                  updateKnownRegistersForInstruction(MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops);
    void                    applyDeferredKnownDefinition(const DeferredDef& deferredKnownDef);
    void                    updateKnownConstantPointersForInstruction(MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops);
    void                    updateKnownAddressesForInstruction(const MicroInstr& inst, const MicroInstrOperand* ops);
    void                    applyDeferredAddressDefinition(const DeferredDef& deferredAddressDef);
    void                    eraseOverlappingStackSlots(uint64_t offset, MicroOpBits opBits);
    void                    setKnownStackSlot(uint64_t offset, MicroOpBits opBits, uint64_t value);
    void                    eraseOverlappingStackAddresses(uint64_t offset, MicroOpBits opBits);
    void                    setKnownStackAddress(uint64_t stackSlotOffset, uint64_t stackAddressOffset);
    bool                    tryGetKnownStackAddress(uint64_t& outStackAddressOffset, uint64_t stackSlotOffset, MicroOpBits opBits) const;
    bool                    tryGetKnownStackSlotValue(uint64_t& outValue, uint64_t offset, MicroOpBits opBits) const;
    bool                    tryResolveStackOffset(uint64_t& outOffset, MicroReg baseReg, uint64_t baseOffset) const;
    bool                    tryResolveStackOffsetForAmc(uint64_t& outOffset, MicroReg baseReg, MicroReg mulReg, uint64_t mulValue, uint64_t addValue) const;
    bool                    callHasStackAddressArgument(CallConvKind callConvKind) const;
    void                    eraseKnownDefs(MicroRegSpan defs);
    void                    eraseKnownAddressDefs(MicroRegSpan defs);
    void                    eraseKnownConstantPointerDefs(MicroRegSpan defs);
    static bool             tryGetPointerBytesRange(std::array<std::byte, 16>& outBytes, uint32_t numBytes, uint64_t pointer, uint64_t offset);
    bool                    constantPointerRangeHasRelocation(const KnownConstantPointer& constantPointer, uint32_t numBytes) const;
    void                    setKnownStackSlotsFromBytes(uint64_t baseOffset, std::span<const std::byte> bytes);
    static uint64_t         signExtendToBits(uint64_t value, MicroOpBits srcBits, MicroOpBits dstBits);
    static bool             foldFloatBinaryToBits(uint64_t& outValue, uint64_t lhs, uint64_t rhs, MicroOp op, MicroOpBits opBits);
    static bool             foldConvertFloatToIntToBits(uint64_t& outValue, uint64_t srcBits, MicroOpBits opBits);
    static BinaryFoldResult tryFoldBinaryImmediateForPropagation(uint64_t& outValue, uint64_t lhs, uint64_t rhs, MicroOp op, MicroOpBits opBits, Math::FoldStatus* outSafetyStatus = nullptr);
    static bool             tryApplyUnsignedAddSubOffset(uint64_t& outValue, uint64_t inValue, uint64_t delta, MicroOp op);
    static void             captureInstrRewriteSnapshot(InstrRewriteSnapshot& outSnapshot, const MicroInstr& inst, const MicroInstrOperand* ops);
    static void             restoreInstrRewriteSnapshot(const InstrRewriteSnapshot& snapshot, MicroInstr& inst, MicroInstrOperand* ops);
    bool                    commitOrRestoreInstrRewrite(const InstrRewriteSnapshot& snapshot, MicroInstr& inst, MicroInstrOperand* ops) const;
    static Math::FoldStatus foldUnaryImmediateToBits(uint64_t& outValue, uint64_t inValue, MicroOp microOp, MicroOpBits opBits);
    void                    rewriteMemoryBaseToKnownStack(const MicroInstr& inst, MicroInstrOperand* ops) const;
    void                    clearRunContext();
    void                    clearState();
    void                    initRunState(MicroPassContext& context);
    void                    collectReferencedLabels();
    void                    updateCompareStateForInstruction(const MicroInstr& inst, MicroInstrOperand* ops, std::optional<std::pair<MicroReg, uint64_t>>& deferredKnownDef);
    void                    clearControlFlowBoundaryForInstruction(const MicroInstr& inst, const MicroInstrOperand* ops);
    void                    clearForCallBoundary(CallConvKind callConvKind);

    KnownRegMap                                               known_;
    KnownStackSlotMap                                         knownStackSlots_;
    KnownAddressMap                                           knownAddresses_;
    KnownStackAddressMap                                      knownStackAddresses_;
    KnownConstantPointerMap                                   knownConstantPointers_;
    CompareState                                              compareState_;
    std::unordered_map<MicroInstrRef, const MicroRelocation*> relocationByInstructionRef_;
    std::unordered_set<MicroLabelRef>                         referencedLabels_;
    MicroPassContext*                                         context_  = nullptr;
    MicroStorage*                                             storage_  = nullptr;
    MicroOperandStorage*                                      operands_ = nullptr;
    MicroReg                                                  stackPointerReg_;
};

SWC_END_NAMESPACE();
