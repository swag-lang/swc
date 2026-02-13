#pragma once
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

namespace Backend::Unittest
{
    bool isPersistentReg(const SmallVector<MicroReg>& regs, MicroReg reg);
    void assertNoVirtualRegs(MicroInstrBuilder& builder);
}

SWC_END_NAMESPACE();
