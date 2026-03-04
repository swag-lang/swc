#pragma once
#include "Backend/Runtime.h"

SWC_BEGIN_NAMESPACE();

struct MicroInstr;
struct MicroInstrOperand;

class X64Unwind
{
public:
    explicit X64Unwind(Runtime::TargetOs targetOs) :
        targetOs_(targetOs)
    {
    }

    void buildInfo(std::vector<std::byte>& outUnwindInfo, uint32_t codeSize) const;
    void onInstructionEncoded(const MicroInstr& inst, const MicroInstrOperand* ops, uint32_t codeStartOffset, uint32_t codeEndOffset);

private:
    struct UnwindComputer
    {
        void (X64Unwind::*buildInfo)(std::vector<std::byte>& outUnwindInfo, uint32_t codeSize) const                                                = nullptr;
        void (X64Unwind::*trackInstruction)(const MicroInstr& inst, const MicroInstrOperand* ops, uint32_t codeStartOffset, uint32_t codeEndOffset) = nullptr;
    };

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

    static const UnwindComputer& unwindComputerForOs(Runtime::TargetOs targetOs);

    void buildInfoUnsupported(std::vector<std::byte>& outUnwindInfo, uint32_t codeSize) const;
    void buildInfoWindows(std::vector<std::byte>& outUnwindInfo, uint32_t codeSize) const;
    void onInstructionEncodedWindows(const MicroInstr& inst, const MicroInstrOperand* ops, uint32_t codeStartOffset, uint32_t codeEndOffset);

    bool tryTrackUnwindPushWindows(const MicroInstrOperand* ops, uint32_t codeEndOffset);
    bool tryTrackUnwindAllocateStackWindows(const MicroInstrOperand* ops, uint32_t codeEndOffset);
    bool tryTrackUnwindSetFramePointerWindows(const MicroInstr& inst, const MicroInstrOperand* ops, uint32_t codeEndOffset);
    bool tryTrackUnwindSaveNonVolWindows(const MicroInstrOperand* ops, uint32_t codeEndOffset);
    void closeUnwindProlog();
    bool canTrackUnwindInstruction(uint32_t codeEndOffset);

    Runtime::TargetOs     targetOs_                 = Runtime::TargetOs::Windows;
    bool                  unwindPrologClosed_       = false;
    bool                  unwindPrologInvalid_      = false;
    bool                  unwindHasFrameRegister_   = false;
    uint8_t               unwindPrologSize_         = 0;
    uint8_t               unwindFrameRegister_      = 0;
    uint8_t               unwindFrameOffsetInSlots_ = 0;
    std::vector<UnwindOp> unwindOps_;
};

SWC_END_NAMESPACE();
