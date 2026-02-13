#include "pch.h"
#include "Backend/MachineCode/CallConv.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr size_t K_CALL_CONV_COUNT = static_cast<size_t>(CallConvKind::Host) + 1;
    CallConv         g_CallConvs[K_CALL_CONV_COUNT];
    bool             g_CallConvsReady = false;

    CallConvKind resolveHostCallConvKind()
    {
#if defined(_WIN32) && defined(_M_X64)
        return CallConvKind::WindowsX64;
#else
        SWC_UNREACHABLE();
#endif
    }

    void setupCallConvWindowsX64(CallConv& conv)
    {
        conv.name         = "WindowsX64";
        conv.stackPointer = MicroReg::intReg(4);
        conv.framePointer = MicroReg::intReg(5);
        conv.intReturn    = MicroReg::intReg(0);
        conv.floatReturn  = MicroReg::floatReg(0);

        conv.intRegs = SmallVector{
            MicroReg::intReg(0),
            MicroReg::intReg(1),
            MicroReg::intReg(2),
            MicroReg::intReg(3),
            MicroReg::intReg(5),
            MicroReg::intReg(6),
            MicroReg::intReg(7),
            MicroReg::intReg(8),
            MicroReg::intReg(9),
            MicroReg::intReg(10),
            MicroReg::intReg(11),
            MicroReg::intReg(12),
            MicroReg::intReg(13),
            MicroReg::intReg(14),
            MicroReg::intReg(15),
        };

        conv.floatRegs = SmallVector{
            MicroReg::floatReg(0),
            MicroReg::floatReg(1),
            MicroReg::floatReg(2),
            MicroReg::floatReg(3),
        };

        conv.intArgRegs = SmallVector{
            MicroReg::intReg(2),
            MicroReg::intReg(3),
            MicroReg::intReg(8),
            MicroReg::intReg(9),
        };

        conv.floatArgRegs = SmallVector{
            MicroReg::floatReg(0),
            MicroReg::floatReg(1),
            MicroReg::floatReg(2),
            MicroReg::floatReg(3),
        };

        conv.intTransientRegs = SmallVector{
            MicroReg::intReg(0),
            MicroReg::intReg(2),
            MicroReg::intReg(3),
            MicroReg::intReg(8),
            MicroReg::intReg(9),
            MicroReg::intReg(10),
            MicroReg::intReg(11),
        };

        conv.intPersistentRegs = SmallVector{
            MicroReg::intReg(1),
            MicroReg::intReg(5),
            MicroReg::intReg(6),
            MicroReg::intReg(7),
            MicroReg::intReg(12),
            MicroReg::intReg(13),
            MicroReg::intReg(14),
            MicroReg::intReg(15),
        };

        conv.floatTransientRegs = SmallVector{
            MicroReg::floatReg(0),
            MicroReg::floatReg(1),
            MicroReg::floatReg(2),
            MicroReg::floatReg(3),
        };

        conv.floatPersistentRegs.clear();
        conv.stackAlignment      = 16;
        conv.stackParamAlignment = 8;
        conv.stackShadowSpace    = 32;
        conv.stackRedZone        = false;
    }
}

void CallConv::setup()
{
    if (g_CallConvsReady)
        return;

    setupCallConvWindowsX64(g_CallConvs[static_cast<size_t>(CallConvKind::WindowsX64)]);

    const auto hostCallConvKind = resolveHostCallConvKind();
    g_CallConvs[static_cast<size_t>(CallConvKind::Host)] = g_CallConvs[static_cast<size_t>(hostCallConvKind)];
    g_CallConvs[static_cast<size_t>(CallConvKind::Host)].name = "Host";
    g_CallConvs[static_cast<size_t>(CallConvKind::C)]    = g_CallConvs[static_cast<size_t>(hostCallConvKind)];
    g_CallConvs[static_cast<size_t>(CallConvKind::C)].name = "C";

    g_CallConvsReady = true;
}

const CallConv& CallConv::get(CallConvKind kind)
{
    SWC_ASSERT(g_CallConvsReady);
    const auto index = static_cast<size_t>(kind);
    SWC_ASSERT(index < K_CALL_CONV_COUNT);
    return g_CallConvs[index];
}

SWC_END_NAMESPACE();
