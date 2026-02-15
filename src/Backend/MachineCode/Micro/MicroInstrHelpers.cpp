#include "pch.h"
#include "Backend/MachineCode/Micro/MicroInstrHelpers.h"

SWC_BEGIN_NAMESPACE();

bool MicroInstrHelpers::containsReg(std::span<const MicroReg> regs, MicroReg reg)
{
    for (const auto value : regs)
    {
        if (value == reg)
            return true;
    }

    return false;
}

void MicroInstrHelpers::emitMemCopy(MicroInstrBuilder& builder, MicroReg dstReg, MicroReg srcReg, MicroReg tmpReg, uint32_t sizeInBytes)
{
    uint64_t offset = 0;
    uint32_t remain = sizeInBytes;

    while (remain >= 8)
    {
        builder.encodeLoadRegMem(tmpReg, srcReg, offset, MicroOpBits::B64, EncodeFlagsE::Zero);
        builder.encodeLoadMemReg(dstReg, offset, tmpReg, MicroOpBits::B64, EncodeFlagsE::Zero);
        offset += 8;
        remain -= 8;
    }

    if (remain >= 4)
    {
        builder.encodeLoadRegMem(tmpReg, srcReg, offset, MicroOpBits::B32, EncodeFlagsE::Zero);
        builder.encodeLoadMemReg(dstReg, offset, tmpReg, MicroOpBits::B32, EncodeFlagsE::Zero);
        offset += 4;
        remain -= 4;
    }

    if (remain >= 2)
    {
        builder.encodeLoadRegMem(tmpReg, srcReg, offset, MicroOpBits::B16, EncodeFlagsE::Zero);
        builder.encodeLoadMemReg(dstReg, offset, tmpReg, MicroOpBits::B16, EncodeFlagsE::Zero);
        offset += 2;
        remain -= 2;
    }

    if (remain >= 1)
    {
        builder.encodeLoadRegMem(tmpReg, srcReg, offset, MicroOpBits::B8, EncodeFlagsE::Zero);
        builder.encodeLoadMemReg(dstReg, offset, tmpReg, MicroOpBits::B8, EncodeFlagsE::Zero);
    }
}

SWC_END_NAMESPACE();
