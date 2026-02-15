#pragma once
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

namespace MicroInstrHelpers
{
    bool containsReg(std::span<const MicroReg> regs, MicroReg reg);
}

SWC_END_NAMESPACE();
