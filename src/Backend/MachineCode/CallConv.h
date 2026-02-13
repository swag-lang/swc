#pragma once
#include "Backend/MachineCode/Micro/MicroReg.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

enum class CallConvKind : uint8_t
{
    C,
    WindowsX64,
    Host,
};

struct CallConv
{
    MicroReg stackPointer = MicroReg::invalid();
    MicroReg framePointer = MicroReg::invalid();
    MicroReg intReturn    = MicroReg::invalid();
    MicroReg floatReturn  = MicroReg::invalid();

    SmallVector<MicroReg> intRegs;
    SmallVector<MicroReg> floatRegs;

    SmallVector<MicroReg> intArgRegs;
    SmallVector<MicroReg> floatArgRegs;

    SmallVector<MicroReg> intTransientRegs;
    SmallVector<MicroReg> intPersistentRegs;

    SmallVector<MicroReg> floatTransientRegs;
    SmallVector<MicroReg> floatPersistentRegs;

    uint32_t stackAlignment       = 0;
    uint32_t stackParamAlignment  = 0;
    uint32_t stackParamSlotSize   = 0;
    uint32_t stackShadowSpace     = 0;
    uint32_t argRegisterSlotCount = 0;

    bool stackRedZone = false;

    uint32_t numArgRegisterSlots() const;
    uint32_t stackSlotSize() const;
    bool     isIntArgReg(MicroReg reg) const;
    bool     tryPickIntScratchRegs(MicroReg& outReg0, MicroReg& outReg1, std::span<const MicroReg> forbidden = {}) const;

    static void            setup();
    static const CallConv& get(CallConvKind kind);
};

SWC_END_NAMESPACE();
