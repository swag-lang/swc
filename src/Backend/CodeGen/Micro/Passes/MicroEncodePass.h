#pragma once
#include "Backend/CodeGen/Encoder/Encoder.h"
#include "Backend/CodeGen/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroEncodePass final : public MicroPass
{
public:
    MicroPassKind kind() const override { return MicroPassKind::Encode; }
    void          run(MicroPassContext& context) override;

private:
    struct PendingLabelJump
    {
        MicroJump   jump;
        uint64_t    labelRef = INVALID_REF;
        EncodeFlags emitFlags;
    };

    void encodeInstruction(const MicroPassContext& context, const MicroInstr& inst);

    std::unordered_map<Ref, uint64_t>  labelOffsets_;
    std::vector<PendingLabelJump>      pendingLabelJumps_;
};

SWC_END_NAMESPACE();
