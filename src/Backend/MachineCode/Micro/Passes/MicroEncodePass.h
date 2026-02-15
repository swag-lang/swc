#pragma once
#include "Backend/MachineCode/Encoder/Encoder.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

struct MicroJump;

class MicroEncodePass final : public MicroPass
{
public:
    void run(MicroPassContext& context) override;

private:
    void encodeInstruction(const MicroPassContext& context, const MicroInstr& inst, size_t idx);
    void buildSavedRegsPlan(const MicroPassContext& context, const CallConv& conv);
    void encodeSavedRegsPrologue(const MicroPassContext& context, const CallConv& conv) const;
    void encodeSavedRegsEpilogue(const MicroPassContext& context, const CallConv& conv, EncodeFlags emitFlags) const;
    bool containsSavedSlot(MicroReg reg) const;

    struct SavedRegSlot
    {
        MicroReg    reg      = MicroReg::invalid();
        uint64_t    offset   = 0;
        MicroOpBits slotBits = MicroOpBits::Zero;
    };

    uint64_t                  savedRegsFrameSize_ = 0;
    std::vector<SavedRegSlot> savedRegSlots_;
    std::vector<MicroJump>    jumps_;
};

SWC_END_NAMESPACE();
