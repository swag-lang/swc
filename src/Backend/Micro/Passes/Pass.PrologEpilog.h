#pragma once
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroTypes.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

struct CallConv;

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
    void buildSavedRegsPlan(MicroPassContext& context, const CallConv& conv);
    void insertSavedRegsPrologue(const MicroPassContext& context, const CallConv& conv, MicroInstrRef insertBeforeRef) const;
    void insertSavedRegsEpilogue(const MicroPassContext& context, const CallConv& conv, MicroInstrRef insertBeforeRef) const;
    bool containsSavedSlot(MicroReg reg) const;

    uint64_t savedRegsStackSubSize_ = 0;
    // When the body's whole stack shape is one subtract at entry and one add
    // before each return, the saved-register area is folded into that single
    // allocation instead of taking one of its own. The unwind description then
    // covers the whole prologue - pushes, one allocation, the float saves at
    // final-rsp-relative offsets - and the frame register is no longer owed.
    bool                      mergedIntoBodyAllocation_ = false;
    uint64_t                  bodyAllocationSize_       = 0;
    bool                      useFramePointer_          = false;
    SmallVector<MicroReg>     pushedRegs_;
    std::vector<SavedRegSlot> savedRegSlots_;
};

SWC_END_NAMESPACE();
