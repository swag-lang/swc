#pragma once
#include "Backend/CodeGen/Encoder/Encoder.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace Backend::Unittest
{
    struct ExpectedByte
    {
        uint8_t value    = 0;
        bool    wildcard = false;
    };

    Result parseExpected(const char* text, std::vector<ExpectedByte>& result);
    Result runEncodeCase(TaskContext& ctx, Encoder& encoder, const char* name, const char* expectedHex, const std::function<void(MicroInstrBuilder&)>& fn);

    bool   isPersistentReg(const SmallVector<MicroReg>& regs, MicroReg reg);
    Result assertNoVirtualRegs(MicroInstrBuilder& builder);
}

#endif

SWC_END_NAMESPACE();
