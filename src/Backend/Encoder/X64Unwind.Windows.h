#pragma once
#include "Backend/Encoder/X64Unwind.h"

SWC_BEGIN_NAMESPACE();

class X64UnwindWindows final : public X64Unwind
{
public:
    void buildInfo(std::vector<std::byte>& outUnwindInfo, uint32_t codeSize) const override;
    void onInstructionEncoded(const MicroInstr& inst, const MicroInstrOperand* ops, uint32_t codeStartOffset, uint32_t codeEndOffset) override;

private:
    enum class UnwindOpKind : uint8_t
    {
        PushNonVol,
        AllocateStack,
        SetFramePointer,
        SaveNonVol,
    };

    struct UnwindOp
    {
        UnwindOpKind kind        = UnwindOpKind::PushNonVol;
        uint8_t      codeOffset  = 0;
        uint8_t      reg         = 0;
        uint32_t     stackSize   = 0;
        uint32_t     stackOffset = 0;
    };

    bool tryTrackPush(const MicroInstrOperand* ops, uint32_t codeEndOffset);
    bool tryTrackAllocateStack(const MicroInstrOperand* ops, uint32_t codeEndOffset);
    bool tryTrackSetFramePointer(const MicroInstr& inst, const MicroInstrOperand* ops, uint32_t codeEndOffset);
    bool tryTrackSaveNonVol(const MicroInstrOperand* ops, uint32_t codeEndOffset);
    void closeProlog();
    bool canTrackInstruction(uint32_t codeEndOffset);

    bool                  unwindPrologClosed_       = false;
    bool                  unwindPrologInvalid_      = false;
    bool                  unwindHasFrameRegister_   = false;
    uint8_t               unwindPrologSize_         = 0;
    uint8_t               unwindFrameRegister_      = 0;
    uint8_t               unwindFrameOffsetInSlots_ = 0;
    std::vector<UnwindOp> unwindOps_;
};

SWC_END_NAMESPACE();
