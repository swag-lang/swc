#pragma once
#include "Backend/CodeGen/Encoder/Encoder.h"
#include "Backend/CodeGen/Micro/MicroBuilder.h"
#include "Backend/CodeGen/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroEmitPass final : public MicroPass
{
public:
    MicroPassKind kind() const override { return MicroPassKind::Emit; }
    void          run(MicroPassContext& context) override;

private:
    struct PendingLabelJump
    {
        MicroJump jump;
        uint64_t  labelRef = INVALID_REF;
    };

    void encodeInstruction(const MicroPassContext& context, Ref instructionRef, const MicroInstr& inst);
    void bindAbs64RelocationOffset(const MicroPassContext& context, Ref instructionRef, uint32_t codeStartOffset, uint32_t codeEndOffset) const;

    std::optional<uint32_t> findRelocationIndex(Ref instructionRef) const;

    std::unordered_map<Ref, uint64_t> labelOffsets_;
    std::vector<PendingLabelJump>     pendingLabelJumps_;
    std::unordered_map<Ref, uint32_t> relocationByInstructionRef_;
};

SWC_END_NAMESPACE();
