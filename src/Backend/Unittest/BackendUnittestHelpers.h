#pragma once
#include "Backend/MachineCode/Encoder/Encoder.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace Backend::Unittest
{
    struct ExpectedByte
    {
        uint8_t value    = 0;
        bool    wildcard = false;
    };

    std::vector<ExpectedByte> parseExpected(const char* text);
    void                      runEncodeCase(TaskContext& ctx, Encoder& encoder, const char* name, const char* expectedHex, const std::function<void(MicroInstrBuilder&)>& fn);

    bool isPersistentReg(const SmallVector<MicroReg>& regs, MicroReg reg);
    void assertNoVirtualRegs(MicroInstrBuilder& builder);
}

#endif

SWC_END_NAMESPACE();
