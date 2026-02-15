#pragma once
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

namespace MicroInstrHelpers
{
    bool containsReg(std::span<const MicroReg> regs, MicroReg reg);
    void emitMemCopy(MicroInstrBuilder& builder, MicroReg dstReg, MicroReg srcReg, MicroReg tmpReg, uint32_t sizeInBytes);
}

SWC_END_NAMESPACE();
