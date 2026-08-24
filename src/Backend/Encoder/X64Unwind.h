#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Runtime.h"
#include "Support/Core/ByteArray.h"

SWC_BEGIN_NAMESPACE();

struct MicroInstr;
struct MicroInstrOperand;

class X64Unwind
{
public:
    virtual ~X64Unwind() = default;

    static std::unique_ptr<X64Unwind> create(Runtime::TargetOs targetOs);

    virtual void buildInfo(ByteArray& outUnwindInfo, uint32_t codeSize) const                                                                 = 0;
    virtual void onInstructionEncoded(const MicroInstr& inst, const MicroInstrOperand* ops, uint32_t codeStartOffset, uint32_t codeEndOffset) = 0;

    // The one register the calling convention lets a function keep the frame in.
    // Only that register may be recorded as the unwind frame register, because
    // only that one is guaranteed to still hold the frame when the unwinder
    // reads it. See X64UnwindWindows::tryTrackSetFramePointer.
    virtual void setFrameRegister(MicroReg reg) { SWC_UNUSED(reg); }
};

SWC_END_NAMESPACE();
