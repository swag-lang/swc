#pragma once
#include "Backend/Micro/MicroPassManager.h"

SWC_BEGIN_NAMESPACE();

struct KnownConstant
{
    uint64_t value = 0;
};

struct KnownConstantPointer
{
    uint64_t pointer = 0;
    uint64_t offset  = 0;
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

class MicroConstantPropagationPass final : public MicroPass
{
public:
    std::string_view name() const override { return "const-prop"; }
    Result           run(MicroPassContext& context) override;

private:
    using DeferredDef = std::optional<std::pair<MicroReg, uint64_t>>;

    Result rewriteInstructionFromKnownValues(MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops, DeferredDef& deferredKnownDef, DeferredDef& deferredAddressDef);
    Result rewriteLoadFromMemoryInstructions(MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops, DeferredDef& deferredKnownDef, DeferredDef& deferredAddressDef) const;
    Result rewriteLoadAndMoveInstructions(MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops, const DeferredDef& deferredKnownDef, DeferredDef& deferredAddressDef);
    Result rewriteRegisterOperationInstructions(MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops, DeferredDef& deferredKnownDef, DeferredDef& deferredAddressDef);
    Result rewriteMemoryOperandInstructions(MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops);
    void   invalidateStateForDefinitions(const MicroInstrUseDef& useDef);
    Result trackKnownMemoryWrite(MicroInstrRef instRef, const MicroInstr* prevInst, const MicroInstrOperand* prevOps, const MicroInstr& inst, const MicroInstrOperand* ops);
    Result trackStackStoreInstruction(const MicroInstr* prevInst, const MicroInstrOperand* prevOps, const MicroInstr& inst, const MicroInstrOperand* ops, bool& handledMemoryWrite);
    Result trackStackMutationInstruction(MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops, bool& handledMemoryWrite);
    bool   tryTrackConstantPointerStackCopy(uint64_t stackOffset, MicroOpBits slotOpBits, MicroReg sourceReg, const MicroInstr* prevInst, const MicroInstrOperand* prevOps);
    Result updateKnownRegistersForInstruction(MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops);
    void   applyDeferredKnownDefinition(const DeferredDef& deferredKnownDef);
    void   updateKnownConstantPointersForInstruction(MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops);
    void   updateKnownAddressesForInstruction(const MicroInstr& inst, const MicroInstrOperand* ops);
    void   applyDeferredAddressDefinition(const DeferredDef& deferredAddressDef);
    bool   rewritePhase1MemoryBaseToKnownStack(MicroInstr& inst, MicroInstrOperand* ops) const;
    void   clearRunContext();
    void   clearState();
    void   initRunState(MicroPassContext& context);
    void   collectReferencedLabels();
    void   updateCompareStateForInstruction(const MicroInstr& inst, MicroInstrOperand* ops, std::optional<std::pair<MicroReg, uint64_t>>& deferredKnownDef);
    void   clearControlFlowBoundaryForInstruction(const MicroInstr& inst, const MicroInstrOperand* ops);
    void   clearForCallBoundary(CallConvKind callConvKind);

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
