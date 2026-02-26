#pragma once
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroEmitPass final : public MicroPass
{
public:
    std::string_view name() const override { return "emit"; }
    Result           run(MicroPassContext& context) override;

private:
    struct PendingLabelJump
    {
        MicroJump     jump;
        MicroLabelRef labelRef = MicroLabelRef::invalid();
    };

    void encodeInstruction(const MicroPassContext& context, MicroInstrRef instructionRef, const MicroInstr& inst);
    void bindAbs64RelocationOffset(const MicroPassContext& context, MicroInstrRef instructionRef, uint32_t codeStartOffset, uint32_t codeEndOffset) const;

    std::unordered_map<MicroLabelRef, uint64_t> labelOffsets_;
    std::vector<PendingLabelJump>               pendingLabelJumps_;
    std::unordered_map<MicroInstrRef, uint32_t> relocationByInstructionRef_;
};

SWC_END_NAMESPACE();
