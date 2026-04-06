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
        MicroReg    phys;
        uint64_t    spillOffset = 0;
        MicroOpBits spillBits   = MicroOpBits::B64;
        uint32_t    mappedListIndex = std::numeric_limits<uint32_t>::max();
        bool        mapped      = false;
        bool        hasSpill    = false;
        bool        dirty       = false;
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

    uint32_t        denseVirtualIndex(MicroReg key) const;
    VRegState&      stateForVirtual(MicroReg key);
    const VRegState& stateForVirtual(MicroReg key) const;
    bool            isLiveOut(MicroReg key, uint32_t stamp) const;
    bool            isLiveAcrossCall(MicroReg key) const;
    void            markLiveAcrossCall(MicroReg key);
    bool            requiresCallSpill(MicroReg key) const;
    void            markCallSpill(MicroReg key);
    void            clearCallSpill(MicroReg key);
    static bool     containsKey(MicroRegSpan keys, MicroReg key);
    static void     appendUniqueReg(SmallVector<MicroReg>& regs, MicroReg reg);
    bool            isPersistentPhysReg(MicroReg reg) const;
    bool            isPhysRegForbiddenForVirtual(MicroReg virtKey, MicroReg physReg) const;
    bool            isLiveInAt(MicroReg key, uint32_t instructionIndex) const;
    bool            isConcreteLiveInAt(MicroReg key, uint32_t instructionIndex) const;
    bool            hasFutureConcreteTouchConflict(MicroReg virtKey, MicroReg physReg, uint32_t instructionIndex) const;
    bool            tryTakeAllowedPhysical(SmallVector<MicroReg>& pool, MicroReg virtKey, uint32_t instructionIndex, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive, MicroReg& outPhys) const;
    void            returnToFreePool(MicroReg reg);
    uint32_t        distanceToNextUse(MicroReg key, uint32_t instructionIndex) const;
    void            prepareInstructionData();
    void            analyzeLiveness();
    void            computeCurrentLiveOutBits(uint32_t instructionIndex);
    void            markCurrentVirtualLiveOut(uint32_t stamp);
    void            rebuildCurrentConcreteLiveOutRegs();
    bool            isCurrentConcreteLiveOut(MicroReg key) const;
    void            setupPools();
    void            ensureSpillSlot(VRegState& regState, bool isFloat);
    static uint64_t spillMemOffset(uint64_t spillOffset, int64_t stackDepth);
    void            queueSpillStore(PendingInsert& out, MicroReg physReg, const VRegState& regState, int64_t stackDepth) const;
    void            queueSpillLoad(PendingInsert& out, MicroReg physReg, const VRegState& regState, int64_t stackDepth) const;
    void            applyStackPointerDelta(int64_t& stackDepth, const MicroInstr& inst) const;
    static void     mergeLabelStackDepth(std::unordered_map<MicroLabelRef, int64_t>& labelStackDepth, MicroLabelRef labelRef, int64_t stackDepth);
    bool            isCandidateBetter(MicroReg candidateKey, MicroReg candidateReg, MicroReg currentBestKey, MicroReg currentBestReg, uint32_t instructionIndex, uint32_t stamp) const;
    bool            selectEvictionCandidate(MicroReg requestVirtKey, uint32_t instructionIndex, bool isFloatReg, bool fromPersistentPool, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, uint32_t stamp, bool allowConcreteLive, MicroReg& outVirtKey, MicroReg& outPhys) const;
    FreePools       pickFreePools(const AllocRequest& request);
    bool            tryTakeFreePhysical(const AllocRequest& request, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive, MicroReg& outPhys);
    void            unmapVirtReg(MicroReg virtKey);
    void            mapVirtReg(MicroReg virtKey, MicroReg physReg);
    bool            selectEvictionCandidateWithFallback(MicroReg requestVirtKey, uint32_t instructionIndex, bool isFloatReg, bool preferPersistentPool, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, uint32_t stamp, bool allowConcreteLive, MicroReg& outVirtKey, MicroReg& outPhys) const;
    MicroReg        allocatePhysical(const AllocRequest& request, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void            recordDestructiveAlias(SmallVector<MicroReg>& liveBases, SmallVector<DestructiveAlias>& concreteAliases, MicroReg dstReg, MicroReg baseReg, uint32_t stamp, bool trackVirtualDestConflict) const;
    void            collectDestructiveLoadConstraints(SmallVector<MicroReg>& liveBases, SmallVector<DestructiveAlias>& concreteAliases, const MicroInstr& inst, const MicroInstrOperand* instOps, uint32_t stamp) const;
    MicroReg        assignVirtReg(const AllocRequest& request, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, MicroRegSpan remapForbiddenPhysRegs, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void            spillMappedVirtualsForConcreteTouches(const MicroInstrUseDef& useDef, MicroRegSpan protectedKeys, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void            spillCallLiveOut(uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void            flushAllMappedVirtuals(uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void            clearAllMappedVirtuals();
    void            expireDeadMappings(uint32_t stamp);
    void            rewriteInstructions();
    void            insertSpillFrame() const;

    MicroPassContext*    context_      = nullptr;
    const CallConv*      conv_         = nullptr;
    MicroStorage*        instructions_ = nullptr;
    MicroOperandStorage* operands_     = nullptr;

    uint32_t instructionCount_ = 0;
    uint64_t spillFrameUsed_   = 0;
    bool     hasControlFlow_   = false;
    bool     hasVirtualRegs_   = false;

    std::unordered_map<MicroReg, std::vector<uint32_t>> usePositions_;
    std::unordered_map<MicroReg, std::vector<uint32_t>> concreteTouchPositions_;
    std::vector<MicroInstrUseDef>                       instructionUseDefs_;
    MicroDenseRegIndex                                  denseVirtualRegs_;
    MicroDenseRegIndex                                  denseConcreteRegs_;
    std::vector<SmallVector<uint32_t, 4>>               useVirtualIndices_;
    std::vector<SmallVector<uint32_t, 4>>               defVirtualIndices_;
    std::vector<SmallVector<uint32_t, 4>>               useConcreteIndices_;
    std::vector<SmallVector<uint32_t, 4>>               defConcreteIndices_;
    std::vector<uint64_t>                               liveInVirtualBits_;
    std::vector<uint64_t>                               liveInConcreteBits_;
    std::vector<SmallVector<uint32_t, 2>>               predecessors_;
    std::vector<uint32_t>                               worklist_;
    std::vector<uint8_t>                                inWorklist_;
    std::vector<uint64_t>                               tempOutVirtual_;
    std::vector<uint64_t>                               tempInVirtual_;
    std::vector<uint64_t>                               tempOutConcrete_;
    std::vector<uint64_t>                               tempInConcrete_;
    std::vector<uint32_t>                               liveStampByDenseIndex_;
    std::vector<uint8_t>                                vregsLiveAcrossCall_;
    std::vector<uint8_t>                                callSpillFlags_;
    std::vector<uint32_t>                               mappedVirtualIndices_;
    std::vector<MicroReg>                               currentConcreteLiveOut_;

    std::unordered_set<MicroReg> intPersistentSet_;
    std::unordered_set<MicroReg> floatPersistentSet_;

    SmallVector<MicroReg> freeIntTransient_;
    SmallVector<MicroReg> freeIntPersistent_;
    SmallVector<MicroReg> freeFloatTransient_;
    SmallVector<MicroReg> freeFloatPersistent_;

    std::vector<VRegState>           states_;
    const MicroControlFlowGraph*     controlFlowGraph_ = nullptr;
};

SWC_END_NAMESPACE();
