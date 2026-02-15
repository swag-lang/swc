#include "pch.h"
#include "Backend/CodeGen/Micro/MicroInstrHelpers.h"

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

SWC_END_NAMESPACE();
