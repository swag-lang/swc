#pragma once
#include "Backend/Micro/MicroBuilder.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

// Only ever named through a reference here; the encoder tests include the concrete
// encoder they drive.
class Encoder;

namespace Backend::Unittest
{
    struct ExpectedByte
    {
        uint8_t value    = 0;
        bool    wildcard = false;
    };

    Result parseExpected(const char* text, std::vector<ExpectedByte>& result);
    Result runEncodeCase(TaskContext& ctx, Encoder& encoder, const char* name, const char* expectedHex, const std::function<void(MicroBuilder&)>& fn);

    bool   isPersistentReg(MicroRegSpan regs, MicroReg reg);
    Result assertNoVirtualRegs(MicroBuilder& builder);
    // How many times an opcode occurs in what the builder has emitted so far.
    uint32_t countOpcode(const MicroBuilder& builder, MicroInstrOpcode opcode);
}

#endif

SWC_END_NAMESPACE();
