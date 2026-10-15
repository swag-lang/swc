#pragma once
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class MicroEmitPass final : public MicroPass
{
public:
    std::string_view name() const override { return "emit"; }
    Result           run(MicroPassContext& context) override;
    void             setAlignLoopHeaders(bool align) { alignLoopHeaders_ = align; }

private:
    struct PendingLabelJump
    {
        MicroJump     jump;
        MicroInstrRef instructionRef;
        MicroLabelRef labelRef      = MicroLabelRef::invalid();
        uint32_t      paddingBefore = 0;
        uint32_t      groupStart    = 0; // the fused compare when there is one, else the jump
        uint32_t      groupEnd      = 0;
    };

    // The first instruction of a macro-fusible pair, as LLVM's X86 classifyFirstOpcodeInMacroFusion.
    enum class FusionKind : uint8_t
    {
        None,
        Test,
        And,
        Cmp,
        AddSub,
    };

    static FusionKind fusionKind(const MicroInstr& inst, const MicroInstrOperand* ops);
    static bool       isMacroFused(FusionKind first, MicroCond cond);
    void              collectLoopHeaders(const MicroPassContext& context);
    bool              pinLoopBranchGroups();
    void              encodeInstruction(const MicroPassContext& context, MicroInstrRef instructionRef, const MicroInstr& inst);
    void              bindAbs64RelocationOffset(const MicroPassContext& context, uint32_t relocationIndex, uint32_t codeStartOffset, uint32_t codeEndOffset) const;
    void              bindRel32RelocationOffset(const MicroPassContext& context, MicroInstrRef instructionRef, uint32_t codeStartOffset, uint32_t codeEndOffset, uint32_t trailingBytes = 0) const;

    // Labels, instruction slots and relocations are small dense indices, so what the pass knows
    // about each one lives in a table indexed by it. An entry belongs to the current function or
    // layout when it carries that function's or layout's stamp: the tables are kept across
    // functions and never cleared, and a lookup allocates nothing.
    struct LabelInfo
    {
        uint64_t offset          = 0;
        uint32_t paddingBefore   = 0;
        uint32_t offsetStamp     = 0; // layout
        uint32_t seenStamp       = 0; // function
        uint32_t loopHeaderStamp = 0; // function
        uint32_t pinnedStamp     = 0; // function
        uint32_t pinnedPhase     = 0;
    };

    struct SlotInfo
    {
        uint32_t relocationIndex = 0;
        uint32_t relocationStamp = 0; // function
        uint32_t shortJumpStamp  = 0; // short-jump epoch
    };

    struct PinCandidate
    {
        MicroLabelRef labelRef = MicroLabelRef::invalid();
        uint32_t      start    = 0;
        uint32_t      end      = 0;
    };

    LabelInfo&       labelInfo(MicroLabelRef labelRef);
    const LabelInfo* findLabelInfo(MicroLabelRef labelRef) const;
    bool             findRelocationIndex(uint32_t& outIndex, MicroInstrRef instructionRef) const;
    bool             isShortJump(MicroInstrRef instructionRef) const;
    void             nextFunctionStamp();
    void             nextLayoutStamp();
    void             nextShortJumpEpoch();

    std::vector<LabelInfo>        labels_;
    std::vector<SlotInfo>         slots_;
    mutable std::vector<uint32_t> boundRelocationStamps_; // layout
    std::vector<PendingLabelJump> pendingLabelJumps_;
    std::vector<PinCandidate>     pinCandidates_;
    uint32_t                      functionStamp_    = 0;
    uint32_t                      layoutStamp_      = 0;
    uint32_t                      shortJumpEpoch_   = 0;
    uint32_t                      paddingBudget_    = 0;
    uint32_t                      pinnedLabels_     = 0;
    uint32_t                      prevInstrStart_   = 0;
    uint32_t                      prevInstrEnd_     = 0;
    FusionKind                    prevFusion_       = FusionKind::None;
    bool                          alignLoopHeaders_ = false;
};

SWC_END_NAMESPACE();
