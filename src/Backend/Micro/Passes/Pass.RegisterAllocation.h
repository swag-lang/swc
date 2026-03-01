#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

struct CallConv;
class MicroStorage;
class MicroOperandStorage;

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

    void clearState();
    void initState(MicroPassContext& context);

    bool            isLiveOut(MicroReg key, uint32_t stamp) const;
    bool            isConcreteLiveOut(MicroReg reg, uint32_t stamp) const;
    static bool     containsKey(MicroRegSpan keys, MicroReg key);
    bool            isPersistentPhysReg(MicroReg reg) const;
    bool            isPhysRegForbiddenForVirtual(MicroReg virtKey, MicroReg physReg) const;
    bool            tryTakeAllowedPhysical(SmallVector<MicroReg>& pool, MicroReg virtKey, uint32_t stamp, bool allowConcreteLive, MicroReg& outPhys) const;
    void            returnToFreePool(MicroReg reg);
    uint32_t        distanceToNextUse(MicroReg key, uint32_t instructionIndex) const;
    void            prepareInstructionData();
    void            analyzeLiveness();
    void            setupPools();
    void            ensureSpillSlot(VRegState& regState, bool isFloat);
    static uint64_t spillMemOffset(uint64_t spillOffset, int64_t stackDepth);
    void            queueSpillStore(PendingInsert& out, MicroReg physReg, const VRegState& regState, int64_t stackDepth) const;
    void            queueSpillLoad(PendingInsert& out, MicroReg physReg, const VRegState& regState, int64_t stackDepth) const;
    void            applyStackPointerDelta(int64_t& stackDepth, const MicroInstr& inst) const;
    static void     mergeLabelStackDepth(std::unordered_map<MicroLabelRef, int64_t>& labelStackDepth, MicroLabelRef labelRef, int64_t stackDepth);
    bool            isCandidateBetter(MicroReg candidateKey, MicroReg candidateReg, MicroReg currentBestKey, MicroReg currentBestReg, uint32_t instructionIndex, uint32_t stamp) const;
    bool            selectEvictionCandidate(MicroReg     requestVirtKey,
                                            uint32_t     instructionIndex,
                                            bool         isFloatReg,
                                            bool         fromPersistentPool,
                                            MicroRegSpan protectedKeys,
                                            uint32_t     stamp,
                                            bool         allowConcreteLive,
                                            MicroReg&    outVirtKey,
                                            MicroReg&    outPhys) const;
    FreePools       pickFreePools(const AllocRequest& request);
    bool            tryTakeFreePhysical(const AllocRequest& request, uint32_t stamp, bool allowConcreteLive, MicroReg& outPhys);
    void            unmapVirtReg(MicroReg virtKey);
    void            mapVirtReg(MicroReg virtKey, MicroReg physReg);
    bool            selectEvictionCandidateWithFallback(MicroReg     requestVirtKey,
                                                        uint32_t     instructionIndex,
                                                        bool         isFloatReg,
                                                        bool         preferPersistentPool,
                                                        MicroRegSpan protectedKeys,
                                                        uint32_t     stamp,
                                                        bool         allowConcreteLive,
                                                        MicroReg&    outVirtKey,
                                                        MicroReg&    outPhys) const;
    MicroReg        allocatePhysical(const AllocRequest& request, MicroRegSpan protectedKeys, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    MicroReg        assignVirtReg(const AllocRequest& request, MicroRegSpan protectedKeys, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void            spillCallLiveOut(uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending);
    void            flushAllMappedVirtuals(int64_t stackDepth, std::vector<PendingInsert>& pending);
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

    std::vector<std::vector<MicroReg>>                  liveOut_;
    std::vector<std::vector<MicroReg>>                  concreteLiveOut_;
    std::unordered_set<MicroReg>                        vregsLiveAcrossCall_;
    std::unordered_map<MicroReg, std::vector<uint32_t>> usePositions_;
    std::vector<MicroInstrUseDef>                       instructionUseDefs_;

    std::unordered_set<MicroReg> intPersistentSet_;
    std::unordered_set<MicroReg> floatPersistentSet_;

    SmallVector<MicroReg> freeIntTransient_;
    SmallVector<MicroReg> freeIntPersistent_;
    SmallVector<MicroReg> freeFloatTransient_;
    SmallVector<MicroReg> freeFloatPersistent_;

    std::unordered_map<MicroReg, VRegState> states_;
    std::unordered_map<MicroReg, MicroReg>  mapping_;
    std::unordered_map<MicroReg, uint32_t>  liveStamp_;
    std::unordered_map<MicroReg, uint32_t>  concreteLiveStamp_;
    std::unordered_set<MicroReg>            callSpillVregs_;
};

SWC_END_NAMESPACE();
