#pragma once
#include "Backend/Encoder/X64Unwind.h"

SWC_BEGIN_NAMESPACE();

class X64UnwindWindows final : public X64Unwind
{
public:
    void buildInfo(ByteArray& outUnwindInfo, uint32_t codeSize) const override;
    void onInstructionEncoded(const MicroInstr& inst, const MicroInstrOperand* ops, uint32_t codeStartOffset, uint32_t codeEndOffset) override;
    void setFrameRegister(MicroReg reg) override { abiFrameRegister_ = reg; }

private:
    enum class UnwindOpKind : uint8_t
    {
        PushNonVol,
        AllocateStack,
        SetFramePointer,
        SaveXmm128,
    };

    struct UnwindOp
    {
        UnwindOpKind kind       = UnwindOpKind::PushNonVol;
        uint8_t      codeOffset = 0;
        uint8_t      reg        = 0;
        uint32_t     stackSize  = 0;
    };

    bool tryTrackPush(const MicroInstrOperand* ops, uint32_t codeEndOffset);
    bool tryTrackAllocateStack(const MicroInstrOperand* ops, uint32_t codeEndOffset);
    bool tryTrackSetFramePointer(const MicroInstr& inst, const MicroInstrOperand* ops, uint32_t codeEndOffset);
    bool tryTrackSaveXmm128(const MicroInstrOperand* ops, uint32_t codeEndOffset);
    void closeProlog();
    bool canTrackInstruction(uint32_t codeEndOffset);

    MicroReg              abiFrameRegister_         = MicroReg::invalid();
    bool                  unwindPrologClosed_       = false;
    bool                  unwindHasStackAllocation_ = false;
    bool                  unwindHasFrameRegister_   = false;
    uint8_t               unwindPrologSize_         = 0;
    uint8_t               unwindFrameRegister_      = 0;
    uint8_t               unwindFrameOffsetInSlots_ = 0;
    uint16_t              unwindPushedRegMask_      = 0;
    std::vector<UnwindOp> unwindOps_;
};

SWC_END_NAMESPACE();
