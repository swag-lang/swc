#include "pch.h"
#include "Backend/Unittest/BackendUnittestHelpers.h"
#include "Backend/MachineCode/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

namespace Backend::Unittest
{
    bool isPersistentReg(const SmallVector<MicroReg>& regs, MicroReg reg)
    {
        return std::ranges::find(regs, reg) != regs.end();
    }

    void assertNoVirtualRegs(MicroInstrBuilder& builder)
    {
        auto& storeOps = builder.operands().store();
        for (const auto& inst : builder.instructions().view())
        {
            SmallVector<MicroInstrRegOperandRef> regs;
            inst.collectRegOperands(storeOps, regs, nullptr);
            for (const auto& regRef : regs)
                SWC_ASSERT(regRef.reg && !regRef.reg->isVirtual());
        }
    }
}

SWC_END_NAMESPACE();
