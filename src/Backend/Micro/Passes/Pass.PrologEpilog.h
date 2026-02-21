#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroPrologEpilogPass final : public MicroPass
{
public:
    std::string_view name() const override { return "prolog-epilog"; }
    bool             run(MicroPassContext& context) override;

private:
    struct SavedRegSlot
    {
        MicroReg    reg      = MicroReg::invalid();
        uint64_t    offset   = 0;
        MicroOpBits slotBits = MicroOpBits::Zero;
    };

    bool containsPushedReg(MicroReg reg) const;
    void buildSavedRegsPlan(const MicroPassContext& context, const CallConv& conv);
    void insertSavedRegsPrologue(const MicroPassContext& context, const CallConv& conv, Ref insertBeforeRef) const;
    void insertSavedRegsEpilogue(const MicroPassContext& context, const CallConv& conv, Ref insertBeforeRef) const;
    bool containsSavedSlot(MicroReg reg) const;

    uint64_t                  savedRegsStackSubSize_ = 0;
    bool                      useFramePointer_       = false;
    SmallVector<MicroReg>     pushedRegs_;
    std::vector<SavedRegSlot> savedRegSlots_;
};

SWC_END_NAMESPACE();
