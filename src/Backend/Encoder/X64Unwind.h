#pragma once
#include "Backend/Runtime.h"

SWC_BEGIN_NAMESPACE();

struct MicroInstr;
struct MicroInstrOperand;

class X64Unwind
{
public:
    virtual ~X64Unwind() = default;

    static std::unique_ptr<X64Unwind> create(Runtime::TargetOs targetOs);

    virtual void buildInfo(std::vector<std::byte>& outUnwindInfo, uint32_t codeSize) const                                                    = 0;
    virtual void onInstructionEncoded(const MicroInstr& inst, const MicroInstrOperand* ops, uint32_t codeStartOffset, uint32_t codeEndOffset) = 0;
};

SWC_END_NAMESPACE();
