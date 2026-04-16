#pragma once
#include "Backend/Micro/MicroDenseRegIndex.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class MicroBuilder;
class MicroControlFlowGraph;
struct MicroPassContext;

class MicroSsaState
{
public:
    static constexpr uint32_t K_INVALID_VALUE = std::numeric_limits<uint32_t>::max();
    static constexpr uint32_t K_INVALID_PHI   = std::numeric_limits<uint32_t>::max();

    struct ReachingDef
    {
        uint32_t      valueId = K_INVALID_VALUE;
        MicroInstrRef instRef = MicroInstrRef::invalid();
        MicroInstr*   inst    = nullptr;
        bool          isPhi   = false;

        bool valid() const { return valueId != K_INVALID_VALUE; }
    };

    struct RegValueEntry
    {
        MicroReg reg     = MicroReg::invalid();
        uint32_t valueId = K_INVALID_VALUE;
    };

    struct UseSite
    {
        enum class Kind : uint8_t
        {
            Instruction,
            Phi,
        };

        Kind          kind     = Kind::Instruction;
        MicroInstrRef instRef  = MicroInstrRef::invalid();
        uint32_t      phiIndex = K_INVALID_PHI;
    };

    struct ValueInfo
    {
        MicroReg              reg        = MicroReg::invalid();
        MicroInstrRef         instRef    = MicroInstrRef::invalid();
        uint32_t              blockIndex = 0;
        uint32_t              phiIndex   = K_INVALID_PHI;
        SmallVector2<UseSite> uses;

        bool isPhi() const { return phiIndex != K_INVALID_PHI; }
    };

    struct PhiInfo
    {
        MicroReg                 reg           = MicroReg::invalid();
        uint32_t                 regIndex      = K_INVALID_VALUE;
        uint32_t                 blockIndex    = 0;
        uint32_t                 resultValueId = K_INVALID_VALUE;
        SmallVector<uint32_t, 2> predecessorBlocks;
        SmallVector<uint32_t, 2> incomingValueIds;
    };

    void build(MicroBuilder& builder, MicroStorage& storage, MicroOperandStorage& operands, const Encoder* encoder);

    // Returns the shared SSA from the pass context if available, rebuilding it
    // lazily if invalid. Otherwise builds it into 'localState' and returns that.
    // Used by passes that may run either inside the pre-RA optimization loop
    // (shared SSA) or standalone.
    static const MicroSsaState* ensureFor(const MicroPassContext& context, MicroSsaState& localState);

    void clear();
    void invalidate();
    bool isValid() const { return valid_; }

    ReachingDef                reachingDef(MicroReg reg, MicroInstrRef beforeInstRef) const;
    bool                       isRegUsedAfter(MicroReg reg, MicroInstrRef afterInstRef) const;
    const MicroInstrUseDef*    instrUseDef(MicroInstrRef instRef) const;
    bool                       defValue(MicroReg reg, MicroInstrRef instRef, uint32_t& outValueId) const;
    const ValueInfo*           valueInfo(uint32_t valueId) const;
    const PhiInfo*             phiInfo(uint32_t phiIndex) const;
    const PhiInfo*             phiInfoForValue(uint32_t valueId) const;
    std::span<const ValueInfo> values() const { return std::span(valueInfos_.data(), valueInfoCount_); }
    std::span<const PhiInfo>   phis() const { return std::span(phiInfos_.data(), phiInfoCount_); }

private:
    struct InstrInfo
    {
        MicroInstrRef               instRef = MicroInstrRef::invalid();
        MicroInstrUseDef            useDef;
        SmallVector4<RegValueEntry> defValues;
        SmallVector4<uint32_t>      useRegIndices;
        SmallVector4<uint32_t>      defRegIndices;
    };

    struct BlockInfo
    {
        uint32_t                    instructionBegin = 0;
        uint32_t                    instructionEnd   = 0;
        SmallVector<uint32_t, 2>    predecessors;
        SmallVector<uint32_t, 2>    successors;
        SmallVector<uint32_t, 2>    domChildren;
        SmallVector<uint32_t, 2>    dominanceFrontier;
        SmallVector<uint32_t, 2>    phis;
        SmallVector8<RegValueEntry> entryValues;
        uint32_t                    idom = std::numeric_limits<uint32_t>::max();
    };

    struct RenameState
    {
        std::vector<uint32_t> currentValues;
        std::vector<uint32_t> activeRegIndices;
        std::vector<uint32_t> activePositions;
    };

    struct RestorePoint
    {
        uint32_t regIndex    = K_INVALID_VALUE;
        uint32_t previousId  = K_INVALID_VALUE;
        bool     hadPrevious = false;
    };

    static constexpr uint32_t K_INVALID_BLOCK = std::numeric_limits<uint32_t>::max();

    static bool     isTrackedReg(MicroReg reg);
    static uint32_t findRegValue(std::span<const RegValueEntry> entries, MicroReg reg);

    void            resetForBuild(MicroBuilder& builder, MicroStorage& storage, MicroOperandStorage& operands, const Encoder* encoder);
    void            resetInstructionInfos(uint32_t slotCount);
    void            buildBlocks(const MicroControlFlowGraph& controlFlowGraph);
    void            computeDominators();
    void            placePhiNodes();
    void            renameIntoSsa();
    void            renameBlock(uint32_t blockIndex, RenameState& state);
    void            captureCurrentValues(SmallVector8<RegValueEntry>& out, const RenameState& state) const;
    static uint32_t currentValue(const RenameState& state, uint32_t regIndex);
    void            assignPhiInputs(uint32_t predecessorBlock, uint32_t successorBlock, const RenameState& state);
    static void     pushCurrentValue(SmallVector8<RestorePoint>& restores, RenameState& state, uint32_t regIndex, uint32_t valueId);
    uint32_t        createValue(MicroReg reg, uint32_t blockIndex, MicroInstrRef instRef, uint32_t phiIndex);
    uint32_t        createPhi(uint32_t blockIndex, MicroReg reg, uint32_t regIndex);
    void            appendValueUse(uint32_t valueId, const UseSite& useSite);
    bool            isValueTransitivelyUsed(uint32_t valueId) const;

    MicroBuilder*                 builder_  = nullptr;
    MicroStorage*                 storage_  = nullptr;
    MicroOperandStorage*          operands_ = nullptr;
    const Encoder*                encoder_  = nullptr;
    MicroDenseRegIndex            trackedRegs_;
    std::vector<InstrInfo>        instrInfos_;
    std::vector<MicroInstrRef>    instructionRefs_;
    std::vector<uint32_t>         instructionIndexBySlot_;
    std::vector<uint32_t>         instructionToBlock_;
    std::vector<BlockInfo>        blocks_;
    std::vector<ValueInfo>        valueInfos_;
    std::vector<PhiInfo>          phiInfos_;
    mutable std::vector<uint32_t> useVisitStamps_;
    mutable std::vector<uint32_t> useVisitStack_;
    uint32_t                      trackedDefCount_ = 0;
    uint32_t                      valueInfoCount_  = 0;
    uint32_t                      phiInfoCount_    = 0;
    mutable uint32_t              useVisitStamp_   = 1;
    bool                          valid_           = false;
};

SWC_END_NAMESPACE();
