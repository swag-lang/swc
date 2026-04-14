#pragma once
#include "Backend/Micro/MicroDenseRegIndex.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

struct CallConv;
class MicroStorage;
class MicroOperandStorage;
class MicroControlFlowGraph;

class MicroRegisterAllocationPass final : public MicroPass
{
public:
    std::string_view  name() const override { return "regalloc"; }
    MicroRegPrintMode printModeBefore() const override { return MicroRegPrintMode::Virtual; }
    Result            run(MicroPassContext& context) override;
    struct VRegState
    {
        MicroReg          phys;
        uint64_t          spillOffset    = 0;
        MicroOpBits       spillBits      = MicroOpBits::B64;
        MicroInstrOperand rematImmediate = {};
        MicroOpBits       rematBits      = MicroOpBits::B64;
        // Original instruction that defined a rematerializable value. If the value
        // is evicted or expires before any user reads its physical mapping, the
        // defining instruction is unreachable and gets pruned at the end of RA.
        MicroInstrRef rematDefInstRef  = MicroInstrRef::invalid();
        uint32_t      mappedListIndex  = std::numeric_limits<uint32_t>::max();
        bool          mapped           = false;
        bool          hasSpill         = false;
        bool          dirty            = false;
        bool          rematerializable = false;
        bool          rematDefConsumed = false;
    };

private:
    struct PendingInsert
    {
        MicroInstrOpcode  op     = MicroInstrOpcode::Nop;
        uint8_t           numOps = 0;
        MicroInstrOperand ops[4] = {};
    };

    struct AllocRequest
    {
        MicroReg virtReg;
        MicroReg virtKey          = MicroReg::invalid();
        MicroReg preferredPhysReg = MicroReg::invalid();
        MicroReg transferSource   = MicroReg::invalid();
        bool     needsPersistent  = false;
        bool     isUse            = false;
        bool     isDef            = false;
        uint32_t instructionIndex = 0;
    };

    struct FreePools
    {
        SmallVector<MicroReg>* primary   = nullptr;
        SmallVector<MicroReg>* secondary = nullptr;
    };

    struct DestructiveAlias
    {
        MicroReg virtKey = MicroReg::invalid();
        MicroReg physReg = MicroReg::invalid();
    };

    void clearState();
    void initState(MicroPassContext& context);
    void coalesceLocalCopies() const;

    uint32_t         denseVirtualIndex(MicroReg key) const;
    VRegState&       stateForVirtual(MicroReg key);
    const VRegState& stateForVirtual(MicroReg key) const;
    bool             isLiveOut(MicroReg key, uint32_t stamp) const;
    bool             isLiveAcrossCall(MicroReg key) const;
    void             markLiveAcrossCall(MicroReg key);
    bool             requiresCallSpill(MicroReg key) const;
    void             markCallSpill(MicroReg key);
    void             clearCallSpill(MicroReg key);
    static uint32_t  allocRequestPriority(const AllocRequest& request);
    static bool      compareAllocRequests(const AllocRequest& lhs, const AllocRequest& rhs);
    static bool      containsKey(MicroRegSpan keys, MicroReg key);
    static void      appendUniqueReg(SmallVector<MicroReg>& regs, MicroReg reg);
    bool             isPersistentPhysReg(MicroReg reg) const;
    bool             isPhysRegForbiddenForVirtual(MicroReg virtKey, MicroReg physReg) const;
    bool             isLiveInAt(MicroReg key, uint32_t instructionIndex) const;
    bool             isConcreteLiveInAt(MicroReg key, uint32_t instructionIndex) const;
    bool             hasFutureConcreteTouchConflict(MicroReg virtKey, MicroReg physReg, uint32_t instructionIndex) const;
    bool             canUsePhysical(MicroReg virtKey, uint32_t instructionIndex, MicroReg physReg, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive) const;
    bool             tryTakeSpecificPhysical(SmallVector<MicroReg>& pool, MicroReg virtKey, uint32_t instructionIndex, MicroReg preferredPhysReg, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive, MicroReg& outPhys) const;
    bool             tryTakeAllowedPhysical(SmallVector<MicroReg>& pool, MicroReg virtKey, uint32_t instructionIndex, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive, MicroReg& outPhys) const;
    void             returnToFreePool(MicroReg reg);
    uint32_t         distanceToNextUse(MicroReg key, uint32_t instructionIndex) const;
    void             advanceCurrentPositionCursors(uint32_t instructionIndex);
    void             prepareInstructionData();
    void             analyzeLiveness();
    void             computeCurrentLiveOutBits(uint32_t instructionIndex);
    void             markCurrentVirtualLiveOut(uint32_t stamp);
    void             rebuildCurrentConcreteLiveOutRegs();
    bool             canEraseCoalescedCopy(MicroInstrRef copyRef, MicroReg dstReg) const;
    void             mergeVirtualForbiddenRegs(MicroReg dstReg, MicroReg srcReg) const;
    bool             isCurrentConcreteLiveOut(MicroReg key) const;
    void             setupPools();
    void             ensureSpillSlot(VRegState& regState, bool isFloat);
    static void      clearRematerialization(VRegState& regState);
    static void      setRematerializedImmediate(VRegState& regState, const MicroInstrOperand& immediate, MicroOpBits opBits);
    static uint64_t  spillMemOffset(uint64_t spillOffset, int64_t stackDepth);
    static void      queueRematerializedLoad(PendingInsert& out, MicroReg physReg, const VRegState& regState);
    void             queueSpillStore(PendingInsert& out, MicroReg physReg, const VRegState& regState, int64_t stackDepth) const;
    void             queueSpillLoad(PendingInsert& out, MicroReg physReg, const VRegState& regState, int64_t stackDepth) const;
    bool             spillOrRematerializeLiveValue(MicroReg physReg, VRegState& regState, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void             updateRematerializationForDef(VRegState& regState, MicroReg virtKey, MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* instOps) const;
    void             noteRematDefConsumed(VRegState& regState) const;
    void             retireRematDef(VRegState& regState);
    void             queueErase(MicroInstrRef instRef);
    void             flushQueuedErasures();
    void             applyStackPointerDelta(int64_t& stackDepth, const MicroInstr& inst) const;
    static void      mergeLabelStackDepth(std::unordered_map<MicroLabelRef, int64_t>& labelStackDepth, MicroLabelRef labelRef, int64_t stackDepth);
    bool             isCandidateBetter(MicroReg candidateKey, MicroReg candidateReg, MicroReg currentBestKey, MicroReg currentBestReg, uint32_t instructionIndex, uint32_t stamp) const;
    bool             selectEvictionCandidate(MicroReg requestVirtKey, uint32_t instructionIndex, bool isFloatReg, bool fromPersistentPool, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, uint32_t stamp, bool allowConcreteLive, MicroReg& outVirtKey, MicroReg& outPhys) const;
    FreePools        pickFreePools(const AllocRequest& request);
    bool             tryTakePreferredPhysical(const AllocRequest& request, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive, MicroReg& outPhys);
    bool             tryTakeFreePhysical(const AllocRequest& request, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive, MicroReg& outPhys);
    void             unmapVirtReg(MicroReg virtKey);
    void             mapVirtReg(MicroReg virtKey, MicroReg physReg);
    bool             tryTransferCopySource(const AllocRequest& request, MicroRegSpan forbiddenPhysRegs, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending, bool allowLiveSourceSpill, bool allowConcreteLive, MicroReg& outPhys);
    bool             selectEvictionCandidateWithFallback(MicroReg requestVirtKey, uint32_t instructionIndex, bool isFloatReg, bool preferPersistentPool, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, uint32_t stamp, bool allowConcreteLive, MicroReg& outVirtKey, MicroReg& outPhys) const;
    MicroReg         allocatePhysical(const AllocRequest& request, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void             recordDestructiveAlias(SmallVector<MicroReg>& liveBases, SmallVector<DestructiveAlias>& concreteAliases, MicroReg dstReg, MicroReg baseReg, uint32_t stamp, bool trackVirtualDestConflict) const;
    void             collectDestructiveLoadConstraints(SmallVector<MicroReg>& liveBases, SmallVector<DestructiveAlias>& concreteAliases, const MicroInstr& inst, const MicroInstrOperand* instOps, uint32_t stamp) const;
    MicroReg         assignVirtReg(const AllocRequest& request, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, MicroRegSpan remapForbiddenPhysRegs, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void             spillMappedVirtualsForConcreteTouches(const MicroInstrUseDef& useDef, MicroRegSpan protectedKeys, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void             spillCallLiveOut(uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void             flushAllMappedVirtuals(uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void             clearAllMappedVirtuals();
    void             expireDeadMappings(uint32_t stamp);
    void             rewriteInstructions();
    void             insertSpillFrame() const;

    MicroPassContext*    context_      = nullptr;
    const CallConv*      conv_         = nullptr;
    MicroStorage*        instructions_ = nullptr;
    MicroOperandStorage* operands_     = nullptr;

    uint32_t instructionCount_ = 0;
    uint64_t spillFrameUsed_   = 0;
    bool     hasControlFlow_   = false;
    bool     hasVirtualRegs_   = false;

    std::vector<MicroInstrUseDef>         instructionUseDefs_;
    MicroDenseRegIndex                    denseVirtualRegs_;
    MicroDenseRegIndex                    denseConcreteRegs_;
    std::vector<SmallVector<uint32_t, 4>> useVirtualIndices_;
    std::vector<SmallVector<uint32_t, 4>> defVirtualIndices_;
    std::vector<SmallVector<uint32_t, 4>> useConcreteIndices_;
    std::vector<SmallVector<uint32_t, 4>> defConcreteIndices_;
    std::vector<std::vector<uint32_t>>    usePositionsByDenseVirtual_;
    std::vector<std::vector<uint32_t>>    concreteTouchPositionsByDenseIndex_;
    std::vector<uint32_t>                 nextUsePositionCursor_;
    std::vector<uint32_t>                 nextConcreteTouchCursor_;
    std::vector<uint64_t>                 liveInVirtualBits_;
    std::vector<uint64_t>                 liveInConcreteBits_;
    std::vector<SmallVector<uint32_t, 2>> predecessors_;
    std::vector<uint32_t>                 worklist_;
    std::vector<uint8_t>                  inWorklist_;
    std::vector<uint64_t>                 tempOutVirtual_;
    std::vector<uint64_t>                 tempInVirtual_;
    std::vector<uint64_t>                 tempOutConcrete_;
    std::vector<uint64_t>                 tempInConcrete_;
    std::vector<uint32_t>                 definitionCounts_;
    std::vector<uint32_t>                 liveStampByDenseIndex_;
    std::vector<uint8_t>                  vregsLiveAcrossCall_;
    std::vector<uint8_t>                  callSpillFlags_;
    std::vector<uint32_t>                 mappedVirtualIndices_;
    std::vector<MicroReg>                 currentConcreteLiveOut_;

    SmallVector<MicroReg> intPersistentRegs_;
    SmallVector<MicroReg> floatPersistentRegs_;

    SmallVector<MicroReg> freeIntTransient_;
    SmallVector<MicroReg> freeIntPersistent_;
    SmallVector<MicroReg> freeFloatTransient_;
    SmallVector<MicroReg> freeFloatPersistent_;

    std::vector<VRegState>                     states_;
    std::vector<MicroInstrRef>                 pendingErasures_;
    const MicroControlFlowGraph*               controlFlowGraph_ = nullptr;
    std::vector<PendingInsert>                 pending_;
    std::vector<PendingInsert>                 boundaryPending_;
    std::unordered_map<MicroLabelRef, int64_t> labelStackDepth_;
};

SWC_END_NAMESPACE();
