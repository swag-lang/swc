#pragma once
#include "Backend/Micro/MicroPassManager.h"

SWC_BEGIN_NAMESPACE();

class MicroPrologEpilogPass final : public MicroPass
{
public:
    std::string_view name() const override { return "prolog-epilog"; }
    Result           run(MicroPassContext& context) override;

private:
    struct SavedRegSlot
    {
        MicroReg    reg;
        uint64_t    offset   = 0;
        MicroOpBits slotBits = MicroOpBits::Zero;
    };

    bool containsPushedReg(MicroReg reg) const;
    void buildSavedRegsPlan(const MicroPassContext& context, const CallConv& conv);
    void insertSavedRegsPrologue(const MicroPassContext& context, const CallConv& conv, MicroInstrRef insertBeforeRef) const;
    void insertSavedRegsEpilogue(const MicroPassContext& context, const CallConv& conv, MicroInstrRef insertBeforeRef) const;
    bool containsSavedSlot(MicroReg reg) const;

    uint64_t                   savedRegsStackSubSize_ = 0;
    bool                       useFramePointer_       = false;
    SmallVector<MicroReg>      pushedRegs_;
    SmallVector<MicroInstrRef> retRefs_;
    std::vector<SavedRegSlot>  savedRegSlots_;
};

SWC_END_NAMESPACE();
