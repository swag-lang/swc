#pragma once
#include "Backend/CodeGen/Encoder/Encoder.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
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
        MicroJump   jump;
        uint64_t    labelRef = INVALID_REF;
        EncodeFlags emitFlags;
    };

    void encodeInstruction(const MicroPassContext& context, Ref instructionRef, const MicroInstr& inst);

    std::unordered_map<Ref, uint64_t> labelOffsets_;
    std::vector<PendingLabelJump>     pendingLabelJumps_;
    std::unordered_map<Ref, MicroInstrPointerImmediateRelocation> pointerImmediateRelocs_;
};

SWC_END_NAMESPACE();
