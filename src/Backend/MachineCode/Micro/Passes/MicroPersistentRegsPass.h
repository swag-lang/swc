#pragma once
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroPersistentRegsPass final : public MicroPass
{
public:
    MicroPassKind kind() const override { return MicroPassKind::PersistentRegs; }
    void run(MicroPassContext& context) override;

private:
    struct SavedRegSlot
    {
        MicroReg    reg      = MicroReg::invalid();
        uint64_t    offset   = 0;
        MicroOpBits slotBits = MicroOpBits::Zero;
    };

    void buildSavedRegsPlan(const MicroPassContext& context, const CallConv& conv);
    void insertSavedRegsPrologue(const MicroPassContext& context, const CallConv& conv, Ref insertBeforeRef) const;
    void insertSavedRegsEpilogue(const MicroPassContext& context, const CallConv& conv, Ref insertBeforeRef, EncodeFlags emitFlags) const;
    bool containsSavedSlot(MicroReg reg) const;

    uint64_t                  savedRegsFrameSize_ = 0;
    std::vector<SavedRegSlot> savedRegSlots_;
};

SWC_END_NAMESPACE();
