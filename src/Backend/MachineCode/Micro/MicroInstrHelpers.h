#pragma once
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

namespace MicroInstrHelpers
{
    void emitMemCopy(MicroInstrBuilder& builder, MicroReg dstReg, MicroReg srcReg, MicroReg tmpReg, uint32_t sizeInBytes);
}

SWC_END_NAMESPACE();
