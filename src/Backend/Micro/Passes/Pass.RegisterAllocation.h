#pragma once
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroDenseRegIndex.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
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
        // The address of a global, constant or function is materialized by an
        // instruction the emitter patches, so remaking it means remaking its
        // relocation too. Kept by value: the builder's relocation vector grows
        // as remade loads are inserted, which would move any pointer into it.
        MicroRelocation rematRelocation = {};
        bool            rematIsRelocated = false;
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
        // Pinned values live permanently in a reserved callee-saved register for
        // the whole function. They bypass the spill/flush machinery entirely (they
        // are never placed in mappedVirtualIndices_) so loop-carried values stay
        // resident across CFG boundaries instead of round-tripping through memory.
        bool pinned = false;
        // Loop-carried values that could not be pinned are given a stable spill
        // slot up front and may never be rematerialized: the value must round-trip
        // through that one home so the reload at the loop header reads what the
        // redefinition at the back-edge tail wrote. Without a fixed home the linear
        // scan can let the home drift across the back-edge (header reload and tail
        // store land in different slots), silently corrupting the accumulator.
        // See preallocateLoopCarriedSlots.
        bool loopCarriedHome = false;
    };

private:
    struct PendingInsert
    {
        MicroInstrOpcode  op     = MicroInstrOpcode::Nop;
        uint8_t           numOps = 0;
        MicroInstrOperand ops[4] = {};
        // Filled in when the inserted instruction is a remade address load; the
        // insertion site binds it to the fresh instruction.
        MicroRelocation relocation    = {};
        bool            hasRelocation = false;
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

    // Half-open-free span of instruction indices over which a globally assigned
    // value owns its physical register. Two globals may share a register only
    // if their ranges are disjoint, and the local allocator may use it anywhere
    // outside them.
    // A register borrowed from a previous sweep's reservation, and where its
    // saved contents must be read back.
    struct BorrowRestore
    {
        MicroReg    physReg;
        uint64_t    slotOffset = 0;
        MicroOpBits slotBits   = MicroOpBits::B64;
        uint32_t    atIndex    = 0;
    };

    struct GlobalRange
    {
        uint32_t lo         = 0;
        uint32_t hi         = 0;
        uint32_t ownerDense = 0;
    };

    void clearState();
    void initState(MicroPassContext& context);
    void coalesceLocalCopies() const;

    uint32_t         denseVirtualIndex(MicroReg key) const;
    VRegState&       stateForVirtual(MicroReg key);
    const VRegState& stateForVirtual(MicroReg key) const;
    bool             isLiveOut(MicroReg key, uint32_t stamp) const;
    bool             isLiveAcrossCall(MicroReg key) const;
    bool             isLiveAcrossHotCall(MicroReg key) const;
    void             markLiveAcrossCall(MicroReg key);
    void             computeGuardedCallPositions();
    bool             intervalHasHotCall(uint32_t lo, uint32_t hi) const;
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
    void             computeConcreteLoopCarried();
    bool             isConcreteLoopCarried(MicroReg physReg) const;
    bool             hasFutureConcreteTouchConflict(MicroReg virtKey, MicroReg physReg, uint32_t instructionIndex) const;
    bool             canUsePhysical(MicroReg virtKey, uint32_t instructionIndex, MicroReg physReg, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive) const;
    bool             tryTakeSpecificPhysical(SmallVector<MicroReg>& pool, MicroReg virtKey, uint32_t instructionIndex, MicroReg preferredPhysReg, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive, MicroReg& outPhys) const;
    bool             tryTakeAllowedPhysical(SmallVector<MicroReg>& pool, MicroReg virtKey, uint32_t instructionIndex, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive, MicroReg& outPhys) const;
    void             returnToFreePool(MicroReg reg);
    uint32_t         distanceToNextUse(MicroReg key, uint32_t instructionIndex) const;
    void             advanceCurrentPositionCursors(uint32_t instructionIndex);
    void             prepareInstructionData();
    void             computeLoopDepth();
    bool             functionHasCalls() const;
    bool             isFlushBoundary(uint32_t instructionIndex, const MicroInstr& inst) const;
    void             computeVirtualLiveSpans();
    void             computeConcreteClaimPositions();
    void             computeGlobalBenefits(std::vector<uint64_t>& outBenefit) const;
    bool             intervalHasCall(uint32_t lo, uint32_t hi) const;
    bool             concreteClaimsOverlap(MicroReg physReg, uint32_t lo, uint32_t hi) const;
    bool             isProvenFreeRegister(MicroReg physReg) const;
    bool             hullConcreteClaimsBlock(MicroReg physReg, uint32_t lo, uint32_t hi) const;
    bool             isPinnedCallSavedOwner(uint32_t denseIndex) const;
    bool             globalRangesOverlap(MicroReg physReg, uint32_t lo, uint32_t hi) const;
    void             addGlobalRange(MicroReg physReg, uint32_t lo, uint32_t hi, uint32_t ownerDense);
    bool             isReservedByGlobalFor(MicroReg virtKey, MicroReg physReg, uint32_t instructionIndex) const;
    bool             hasConcreteTouchInRange(MicroReg physReg, uint32_t lo, uint32_t hi) const;
    bool             isStraightLineRange(uint32_t lo, uint32_t hi) const;
    bool             tryBorrowReservedRegister(const AllocRequest& request, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, int64_t stackDepth, std::vector<PendingInsert>& pending, MicroReg& outPhys);
    void             assignGlobalRegisters();
    void             preallocateLoopCarriedSlots();
    void             computeReachability();
    void             analyzeLiveness();
    void             computeCurrentLiveOutBits(uint32_t instructionIndex);
    void             markCurrentVirtualLiveOut(uint32_t stamp);
    void             rebuildCurrentConcreteLiveOutRegs();
    bool             isInstructionReachable(uint32_t instructionIndex) const;
    bool             canEraseCoalescedCopy(MicroInstrRef copyRef, MicroReg dstReg) const;
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
    static void      noteRematDefConsumed(VRegState& regState);
    void             retireRematDef(VRegState& regState);
    void             insertPending(MicroInstrRef beforeRef, const PendingInsert& pendingInst);
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
    void             saveRestorePinnedAcrossCall(uint32_t instructionIndex, int64_t stackDepth, std::vector<PendingInsert>& pending);
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
    std::vector<uint32_t>                 loopDepth_;
    std::vector<uint8_t>                  concreteLoopCarried_;
    std::vector<uint32_t>                 virtualSpanLo_;
    std::vector<uint32_t>                 virtualSpanHi_;
    std::vector<std::vector<uint32_t>>    concreteClaimPositionsByDenseIndex_;
    MicroDenseRegIndex                    denseGlobalPhysRegs_;
    std::vector<SmallVector<GlobalRange>> globalRangesByPhysDense_;
    std::vector<uint8_t>                  reachableInstructions_;
    std::vector<uint32_t>                 worklist_;
    std::vector<uint8_t>                  inWorklist_;
    std::vector<uint64_t>                 tempOutVirtual_;
    std::vector<uint64_t>                 tempInVirtual_;
    std::vector<uint64_t>                 tempOutConcrete_;
    std::vector<uint64_t>                 tempInConcrete_;
    std::vector<uint32_t>                 definitionCounts_;
    std::vector<uint32_t>                 liveStampByDenseIndex_;
    std::vector<uint8_t>                  vregsLiveAcrossCall_;
    // Calls sitting inside a forward-jumped-over region — a bounds-check panic
    // block, an error path — never execute on the straight-line path. A value
    // whose only calls are guarded is cheaper parked around them (the cost
    // runs only if the guard fires) than promoted to a callee-saved register
    // (whose save/restore runs on every function entry).
    std::vector<uint8_t>  guardedCallPositions_;
    std::vector<uint8_t>  vregsLiveAcrossHotCall_;
    std::vector<uint8_t>  callSpillFlags_;
    std::vector<uint32_t> mappedVirtualIndices_;
    std::vector<MicroReg> currentConcreteLiveOut_;

    SmallVector<MicroReg> intPersistentRegs_;
    SmallVector<MicroReg> floatPersistentRegs_;

    SmallVector<MicroReg> freeIntTransient_;
    SmallVector<MicroReg> freeIntPersistent_;
    SmallVector<MicroReg> freeFloatTransient_;
    SmallVector<MicroReg> freeFloatPersistent_;

    std::vector<VRegState>       states_;
    std::vector<MicroInstrRef>   pendingErasures_;
    const MicroControlFlowGraph* controlFlowGraph_ = nullptr;
    std::vector<PendingInsert>   pending_;
    SmallVector<BorrowRestore>   pendingBorrowRestores_;
    // Values pinned in a caller-saved register whose hull crosses a call: they
    // are parked in their slot around every call inside the hull
    // (saveRestorePinnedAcrossCall), so the call paths pay for the register
    // instead of the straight-line code.
    SmallVector<uint32_t>      pinnedCallSavedDense_;
    std::vector<PendingInsert> boundaryPending_;
    // Write-through stores for loop-carried values: queued right after the
    // instruction that defines such a value and flushed before the next one, so
    // the value's stable home slot always holds its latest value across the
    // back-edge regardless of when the register mapping is later dropped.
    std::vector<PendingInsert>                 deferredLoopCarriedStores_;
    std::unordered_map<MicroLabelRef, int64_t> labelStackDepth_;
    // Snapshot of what each relocation-bearing address load points at, taken
    // before allocation so a rematerialized copy can be given its own.
    std::unordered_map<MicroInstrRef, MicroRelocation> relocationByDefInstruction_;
};

SWC_END_NAMESPACE();
