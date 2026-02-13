#pragma once
#include "Backend/MachineCode/Encoder/X64Encoder.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

namespace Backend::Unittest
{
    class TestX64Encoder final : public X64Encoder
    {
    public:
        explicit TestX64Encoder(TaskContext& ctx) :
            X64Encoder(ctx)
        {
        }

        uint32_t size() const;
        const uint8_t* data() const;
    };

    bool isPersistentReg(const SmallVector<MicroReg>& regs, MicroReg reg);
    void assertNoVirtualRegs(MicroInstrBuilder& builder);
}

SWC_END_NAMESPACE();
