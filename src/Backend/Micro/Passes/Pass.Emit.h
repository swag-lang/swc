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
        MicroLabelRef labelRef = MicroLabelRef::invalid();
        uint32_t      paddedLabelsBefore = 0;
    };

    void collectLoopHeaders(const MicroPassContext& context);
    void encodeInstruction(const MicroPassContext& context, MicroInstrRef instructionRef, const MicroInstr& inst);
    void bindAbs64RelocationOffset(const MicroPassContext& context, MicroInstrRef instructionRef, uint32_t codeStartOffset, uint32_t codeEndOffset) const;
    void bindRel32RelocationOffset(const MicroPassContext& context, MicroInstrRef instructionRef, uint32_t codeStartOffset, uint32_t codeEndOffset, uint32_t trailingBytes = 0) const;

    std::unordered_map<MicroLabelRef, uint64_t> labelOffsets_;
    std::vector<PendingLabelJump>               pendingLabelJumps_;
    std::unordered_map<MicroInstrRef, uint32_t> relocationByInstructionRef_;
    mutable std::unordered_set<uint32_t>        boundRelocations_;
    std::unordered_set<MicroInstrRef>           shortJumps_;
    std::unordered_set<MicroLabelRef>           loopHeaders_;
    std::unordered_map<MicroLabelRef, uint32_t> paddedLabelsAt_;
    uint32_t                                    paddedLabels_     = 0;
    bool                                        alignLoopHeaders_ = false;
};

SWC_END_NAMESPACE();
