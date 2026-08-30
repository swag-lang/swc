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
        MicroRelocation rematRelocation  = {};
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
        // The defining instruction was pruned because nothing had read the
        // mapping yet. The value is remade wherever it is next needed, so no
        // register can be claimed to hold it any more - which is what a
        // boundary snapshot would otherwise promise.
        bool rematDefErased = false;
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
        // Set when some instruction names this value with a 128-bit operand,
        // which is what decides how wide its spill slot has to be. A float
        // register can hold a vector, so a value that is only ever a scalar
        // double would otherwise pay a 16-byte slot and a 16-byte move for
        // eight bytes of value. See prepareInstructionData.
        bool wideFloat = false;
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

    // A natural loop the residency machinery supports: entered only by
    // falling into its header label, with no jump from outside landing past
    // it, so code placed before the header runs exactly on entry and every
    // other way to the header is a back-edge.
    struct LoopRegion
    {
        uint32_t header = 0;
        uint32_t tail   = 0;
    };

    // One sealed loop the scan is currently inside. Instead of dropping every
    // mapping at the header (the back-edge state is unseen when the linear
    // scan reaches it), the mappings that can survive the loop are kept and
    // recorded, home-resident values the loop reads are preloaded into free
    // registers, and every back-edge restores exactly this state before
    // jumping — so the two sides of the back-edge agree by construction.
    struct LoopResidency
    {
        uint32_t                                      header = 0;
        uint32_t                                      tail   = 0;
        SmallVector<std::pair<uint32_t, MicroReg>, 8> expected;
        // Whether a use read the pair's register through the mapping. Only a
        // consumed pair obligates the back-edge: the emitted body reads that
        // register before any reload, so iteration two must find the value
        // there. A pair broken before anything consumed it is demoted at the
        // next back-edge instead of being refilled forever.
        SmallVector<uint8_t, 8>  consumed;
        SmallVector<uint32_t, 2> backEdges;
    };

    // Register-mapping snapshots recorded at each forward jump, consumed by
    // the join intersection in flushAtBoundary. Keyed by the jump's
    // instruction index; entries pair a dense virtual index with the physical
    // register it occupied on that edge.
    using BoundarySnapshot = SmallVector<std::pair<uint32_t, MicroReg>, 8>;

public:
    // compiler.optimization.024: interval-splitting allocation (Wimmer & Mössenböck, VEE 2005)
    // behind a per-function gate, implemented in
    // Pass.RegisterAllocation.Interval.cpp. Positions number each instruction
    // twice: index*2 is its input (read) slot, index*2+1 its output (write)
    // slot, so a source that dies at an instruction and a destination born
    // there do not overlap.
    struct IntervalRange
    {
        uint32_t from = 0; // inclusive
        uint32_t to   = 0; // exclusive
    };
    struct LiveInterval
    {
        uint32_t                      denseIndex = 0;
        SmallVector<IntervalRange, 4> ranges;       // sorted, disjoint
        SmallVector<uint32_t, 8>      usePositions; // input slots, sorted
        SmallVector<uint32_t, 4>      defPositions; // output slots, sorted

        // Walk state. An interval is one node of a value's split tree: the
        // walk splits at even (instruction-input) positions only, children
        // are re-queued as unhandled, and each node ends with either a
        // register or the value's one spill home.
        MicroReg assignedReg;
        // The register an earlier node of this value held (c1_LinearScan's
        // register hint): re-acquiring it turns the connector at the split
        // into a no-op. hintDense hints across values instead: this value is
        // born from a copy of that one, and taking the same register erases
        // the copy.
        MicroReg hintPhys;
        uint32_t hintDense = std::numeric_limits<uint32_t>::max();
        bool     spilled   = false;

        uint32_t start() const { return ranges.empty() ? 0 : ranges.front().from; }
        uint32_t end() const { return ranges.empty() ? 0 : ranges.back().to; }
        bool     covers(uint32_t pos) const;
        uint32_t nextIntersection(const LiveInterval& other, uint32_t from) const;
        uint32_t firstUseAfter(uint32_t pos) const;
        uint32_t firstRangeStartAfter(uint32_t pos) const;
    };
    struct IntervalWalkResult
    {
        // All split-tree nodes, per original value: [valueNodesBegin[dense],
        // valueNodesBegin[dense+1]) into nodes, sorted by start.
        std::vector<LiveInterval> nodes;
        std::vector<uint32_t>     valueNodesBegin;
        uint32_t                  splitCount = 0;
        uint32_t                  spillCount = 0;
        // The registers the walk allocated from, and the register the debug
        // local-stack base was pinned to (invalid when it was not).
        SmallVector<MicroReg> poolRegs;
        MicroReg              debugStackBasePhys;
    };

private:
    bool intervalAllocationAccepts() const;
    void buildLiveIntervals(std::vector<LiveInterval>& out) const;
    void buildFixedIntervals(std::vector<LiveInterval>& outByPoolIndex, SmallVector<MicroReg>& outPoolRegs) const;
    bool walkIntervals(std::vector<LiveInterval>&& intervals, IntervalWalkResult& out) const;
    bool applyIntervalAllocation(IntervalWalkResult& result);
    bool runIntervalAllocation();

    void clearState();
    void initState(MicroPassContext& context);
    void coalesceLocalCopies() const;

    uint32_t          denseVirtualIndex(MicroReg key) const;
    VRegState&        stateForVirtual(MicroReg key);
    const VRegState&  stateForVirtual(MicroReg key) const;
    bool              isLiveOut(MicroReg key, uint32_t stamp) const;
    bool              isLiveAcrossCall(MicroReg key) const;
    bool              isLiveAcrossHotCall(MicroReg key) const;
    void              markLiveAcrossCall(MicroReg key);
    void              computeGuardedCallPositions();
    bool              intervalHasHotCall(uint32_t lo, uint32_t hi) const;
    bool              requiresCallSpill(MicroReg key) const;
    void              markCallSpill(MicroReg key);
    void              clearCallSpill(MicroReg key);
    static uint32_t   allocRequestPriority(const AllocRequest& request);
    static bool       compareAllocRequests(const AllocRequest& lhs, const AllocRequest& rhs);
    static bool       containsKey(MicroRegSpan keys, MicroReg key);
    static void       appendUniqueReg(SmallVector<MicroReg>& regs, MicroReg reg);
    bool              isPersistentPhysReg(MicroReg reg) const;
    bool              isPoolRegister(MicroReg reg) const;
    bool              isPhysRegForbiddenForVirtual(MicroReg virtKey, MicroReg physReg) const;
    bool              isLiveInAt(MicroReg key, uint32_t instructionIndex) const;
    bool              isConcreteLiveInAt(MicroReg key, uint32_t instructionIndex) const;
    void              computeConcreteLoopCarried();
    bool              isConcreteLoopCarried(MicroReg physReg) const;
    bool              hasFutureConcreteTouchConflict(MicroReg virtKey, MicroReg physReg, uint32_t instructionIndex) const;
    bool              canUsePhysical(MicroReg virtKey, uint32_t instructionIndex, MicroReg physReg, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive) const;
    bool              tryTakeSpecificPhysical(SmallVector<MicroReg>& pool, MicroReg virtKey, uint32_t instructionIndex, MicroReg preferredPhysReg, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive, MicroReg& outPhys) const;
    bool              tryTakeAllowedPhysical(SmallVector<MicroReg>& pool, MicroReg virtKey, uint32_t instructionIndex, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive, MicroReg& outPhys) const;
    void              returnToFreePool(MicroReg reg);
    uint32_t          distanceToNextUse(MicroReg key, uint32_t instructionIndex) const;
    void              advanceCurrentPositionCursors(uint32_t instructionIndex);
    void              prepareInstructionData();
    void              computeLoopDepth();
    bool              functionHasCalls() const;
    bool              isFlushBoundary(uint32_t instructionIndex, const MicroInstr& inst) const;
    void              computeVirtualLiveSpans();
    void              computeConcreteClaimPositions();
    void              computeGlobalBenefits(std::vector<uint64_t>& outBenefit) const;
    void              computeGlobalAccessBenefits(std::vector<uint64_t>& outBenefit) const;
    bool              intervalHasCall(uint32_t lo, uint32_t hi) const;
    bool              concreteClaimsOverlap(MicroReg physReg, uint32_t lo, uint32_t hi) const;
    bool              isProvenFreeRegister(MicroReg physReg) const;
    bool              hullConcreteClaimsBlock(MicroReg physReg, uint32_t lo, uint32_t hi) const;
    bool              isPinnedCallSavedOwner(uint32_t denseIndex) const;
    bool              globalRangesOverlap(MicroReg physReg, uint32_t lo, uint32_t hi) const;
    void              addGlobalRange(MicroReg physReg, uint32_t lo, uint32_t hi, uint32_t ownerDense);
    bool              isReservedByGlobalFor(MicroReg virtKey, MicroReg physReg, uint32_t instructionIndex) const;
    bool              hasConcreteTouchInRange(MicroReg physReg, uint32_t lo, uint32_t hi) const;
    bool              isStraightLineRange(uint32_t lo, uint32_t hi) const;
    bool              tryBorrowReservedRegister(const AllocRequest& request, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, int64_t stackDepth, std::vector<PendingInsert>& pending, MicroReg& outPhys);
    void              collectLoopRegions(SmallVector<LoopRegion>& outRegions) const;
    const LoopRegion* findSealedLoopRegion(uint32_t headerIndex) const;
    bool              isExpectedResident(uint32_t denseIndex) const;
    void              markResidencyConsumed(uint32_t denseIndex, MicroReg physReg);
    void              beginLoopResidency(const LoopRegion& region, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void              conformLoopResidency(uint32_t instructionIndex, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void              assignGlobalRegisters();
    void              preallocateLoopCarriedSlots();
    void              computeReachability();
    void              analyzeLiveness();
    void              computeCurrentLiveOutBits(uint32_t instructionIndex);
    void              markCurrentVirtualLiveOut(uint32_t stamp);
    void              rebuildCurrentConcreteLiveOutRegs();
    bool              isInstructionReachable(uint32_t instructionIndex) const;
    bool              canEraseCoalescedCopy(MicroInstrRef copyRef, MicroReg dstReg) const;
    bool              isCurrentConcreteLiveOut(MicroReg key) const;
    void              setupPools();
    void              ensureSpillSlot(VRegState& regState, bool isFloat);
    static void       clearRematerialization(VRegState& regState);
    static void       setRematerializedImmediate(VRegState& regState, const MicroInstrOperand& immediate, MicroOpBits opBits);
    static uint64_t   spillMemOffset(uint64_t spillOffset, int64_t stackDepth);
    static void       queueRematerializedLoad(PendingInsert& out, MicroReg physReg, const VRegState& regState);
    void              noteSpillAccess(uint64_t offset, MicroOpBits bits);
    void              queueSpillStore(PendingInsert& out, MicroReg physReg, const VRegState& regState, int64_t stackDepth);
    void              queueSpillLoad(PendingInsert& out, MicroReg physReg, const VRegState& regState, int64_t stackDepth);
    bool              spillOrRematerializeLiveValue(MicroReg physReg, VRegState& regState, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void              updateRematerializationForDef(VRegState& regState, MicroReg virtKey, MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* instOps) const;
    static void       noteRematDefConsumed(VRegState& regState);
    void              retireRematDef(VRegState& regState);
    void              insertPending(MicroInstrRef beforeRef, const PendingInsert& pendingInst);
    void              queueErase(MicroInstrRef instRef);
    void              flushQueuedErasures();
    void              applyStackPointerDelta(int64_t& stackDepth, const MicroInstr& inst) const;
    static void       mergeLabelStackDepth(std::unordered_map<MicroLabelRef, int64_t>& labelStackDepth, MicroLabelRef labelRef, int64_t stackDepth);
    bool              isCandidateBetter(MicroReg candidateKey, MicroReg candidateReg, MicroReg currentBestKey, MicroReg currentBestReg, uint32_t instructionIndex, uint32_t stamp) const;
    bool              selectEvictionCandidate(MicroReg requestVirtKey, uint32_t instructionIndex, bool isFloatReg, bool fromPersistentPool, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, uint32_t stamp, bool allowConcreteLive, MicroReg& outVirtKey, MicroReg& outPhys) const;
    FreePools         pickFreePools(const AllocRequest& request);
    bool              tryTakePreferredPhysical(const AllocRequest& request, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive, MicroReg& outPhys);
    bool              tryTakeFreePhysical(const AllocRequest& request, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive, MicroReg& outPhys);
    void              unmapVirtReg(MicroReg virtKey);
    void              mapVirtReg(MicroReg virtKey, MicroReg physReg);
    bool              tryTransferCopySource(const AllocRequest& request, MicroRegSpan forbiddenPhysRegs, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending, bool allowLiveSourceSpill, bool allowConcreteLive, MicroReg& outPhys);
    bool              selectEvictionCandidateWithFallback(MicroReg requestVirtKey, uint32_t instructionIndex, bool isFloatReg, bool preferPersistentPool, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, uint32_t stamp, bool allowConcreteLive, MicroReg& outVirtKey, MicroReg& outPhys) const;
    MicroReg          allocatePhysical(const AllocRequest& request, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void              recordDestructiveAlias(SmallVector<MicroReg>& liveBases, SmallVector<DestructiveAlias>& concreteAliases, MicroReg dstReg, MicroReg baseReg, uint32_t stamp, bool trackVirtualDestConflict) const;
    void              collectDestructiveLoadConstraints(SmallVector<MicroReg>& liveBases, SmallVector<DestructiveAlias>& concreteAliases, const MicroInstr& inst, const MicroInstrOperand* instOps, uint32_t stamp) const;
    MicroReg          assignVirtReg(const AllocRequest& request, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, MicroRegSpan remapForbiddenPhysRegs, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void              spillMappedVirtualsForConcreteTouches(const MicroInstrUseDef& useDef, MicroRegSpan protectedKeys, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void              spillCallLiveOut(uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void              saveRestorePinnedAcrossCall(uint32_t instructionIndex, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void              flushAllMappedVirtuals(uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void              dropMappedVirtualNoStore(uint32_t denseIndex);
    void              flushAtBoundary(uint32_t instructionIndex, const MicroInstr& inst, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void              adoptBoundarySnapshots(uint32_t instructionIndex, std::span<const BoundarySnapshot* const> edgeSnapshots);
    void              clearAllMappedVirtuals();
    void              expireDeadMappings(uint32_t stamp);
    void              rewriteInstructions();
    void              insertSpillFrame() const;

    MicroPassContext*    context_      = nullptr;
    const CallConv*      conv_         = nullptr;
    MicroStorage*        instructions_ = nullptr;
    MicroOperandStorage* operands_     = nullptr;

    uint32_t instructionCount_ = 0;
    uint64_t spillFrameUsed_   = 0;
    uint64_t spillAreaLo_      = std::numeric_limits<uint64_t>::max();
    uint64_t spillAreaHi_      = 0;
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
    bool                                  functionHasLoop_ = false;
    std::vector<uint8_t>                  concreteLoopCarried_;

    // The register each value held on the last control-flow edge that recorded one. Consulted
    // as a preference when a value is given a register again, so the two arms of a diamond
    // tend to leave it in the same place and the join can keep the mapping instead of dropping
    // it. A hint only: the register still has to be free and allowed where it is taken.
    std::vector<MicroReg>                          edgeRegisterHint_;
    std::unordered_map<uint32_t, BoundarySnapshot> boundarySnapshots_;
    bool                                           keepAcrossBoundaries_ = false;
    // Whether the mapping the scan is currently holding belongs to a path that
    // reaches the next instruction. It does after anything that falls through,
    // and it does not after a return or an unconditional jump: what follows one
    // of those is entered through a label, from edges recorded as snapshots.
    bool                                  fallThroughStateValid_ = true;
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
    SmallVector<LoopRegion>    sealedLoopRegions_;
    std::vector<LoopResidency> activeLoopResidency_;
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
