#include "pch.h"
#include "Backend/ABI/CallConv.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr size_t K_CALL_CONV_COUNT = static_cast<size_t>(CallConvKind::Host) + 1;
    CallConv         g_CallConvs[K_CALL_CONV_COUNT];

    CallConvKind resolveHostCallConvKind()
    {
#if defined(_WIN32) && defined(_M_X64)
        return CallConvKind::WindowsX64;
#else
        SWC_UNREACHABLE();
#endif
    }

    bool hasStructSizeBit(uint64_t sizeMask, uint32_t sizeInBytes)
    {
        if (!sizeInBytes || sizeInBytes >= 64)
            return false;

        const uint64_t sizeBit = uint64_t{1} << sizeInBytes;
        return (sizeMask & sizeBit) != 0;
    }

    void setupCallConvWindowsX64(CallConv& conv)
    {
        // Windows x64 ABI model used by both compiled calls and JIT bridge calls.
        conv.name         = "win64";
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
        conv.stackAlignment                            = 16;
        conv.stackParamAlignment                       = 8;
        conv.stackParamSlotSize                        = 8;
        conv.stackShadowSpace                          = 32;
        conv.argRegisterSlotCount                      = 4;
        conv.structArgPassing.passByValueSizeMask      = (uint64_t{1} << 1) | (uint64_t{1} << 2) | (uint64_t{1} << 4) | (uint64_t{1} << 8);
        conv.structArgPassing.passByValueInIntSlots    = true;
        conv.structArgPassing.passByReferenceNeedsCopy = true;
        conv.structReturnPassing.passByValueSizeMask   = (uint64_t{1} << 1) | (uint64_t{1} << 2) | (uint64_t{1} << 4) | (uint64_t{1} << 8);
        conv.stackRedZone                              = false;
    }
}

uint32_t CallConv::numArgRegisterSlots() const
{
    // A call site can only use argument register slots common to int and float lanes.
    if (argRegisterSlotCount)
        return argRegisterSlotCount;

    const uint32_t numIntArgRegs   = static_cast<uint32_t>(intArgRegs.size());
    const uint32_t numFloatArgRegs = static_cast<uint32_t>(floatArgRegs.size());
    return std::min(numIntArgRegs, numFloatArgRegs);
}

uint32_t CallConv::stackSlotSize() const
{
    // Slot granularity used for shadow-space and stack-passed arguments.
    if (stackParamSlotSize)
        return stackParamSlotSize;
    if (stackParamAlignment)
        return stackParamAlignment;
    return sizeof(uint64_t);
}

bool CallConv::canPassStructArgByValue(uint32_t sizeInBytes) const
{
    return hasStructSizeBit(structArgPassing.passByValueSizeMask, sizeInBytes);
}

bool CallConv::canPassStructReturnByValue(uint32_t sizeInBytes) const
{
    return hasStructSizeBit(structReturnPassing.passByValueSizeMask, sizeInBytes);
}

StructArgPassingKind CallConv::classifyStructArgPassing(uint32_t sizeInBytes) const
{
    if (canPassStructArgByValue(sizeInBytes))
        return StructArgPassingKind::ByValue;

    return StructArgPassingKind::ByReference;
}

StructArgPassingKind CallConv::classifyStructReturnPassing(uint32_t sizeInBytes) const
{
    if (canPassStructReturnByValue(sizeInBytes))
        return StructArgPassingKind::ByValue;

    return StructArgPassingKind::ByReference;
}

bool CallConv::isIntArgReg(MicroReg reg) const
{
    for (const auto value : intArgRegs)
    {
        if (value == reg)
            return true;
    }

    return false;
}

bool CallConv::isIntPersistentReg(MicroReg reg) const
{
    for (const auto value : intPersistentRegs)
    {
        if (value == reg)
            return true;
    }

    return false;
}

bool CallConv::isFloatPersistentReg(MicroReg reg) const
{
    for (const auto value : floatPersistentRegs)
    {
        if (value == reg)
            return true;
    }

    return false;
}

bool CallConv::tryPickIntScratchRegs(MicroReg& outReg0, MicroReg& outReg1, std::span<const MicroReg> forbidden) const
{
    // Scratch regs are needed for ABI shuffles; avoid reserved/argument registers first.
    auto isForbidden = [&](MicroReg reg) {
        if (!reg.isValid() || reg == stackPointer || reg == framePointer || reg == intReturn || isIntArgReg(reg))
            return true;

        for (const auto blocked : forbidden)
        {
            if (reg == blocked)
                return true;
        }

        return false;
    };

    outReg0 = MicroReg::invalid();
    outReg1 = MicroReg::invalid();

    auto pickFrom = [&](std::span<const MicroReg> regs) {
        for (const auto reg : regs)
        {
            if (isForbidden(reg))
                continue;

            outReg0 = reg;
            break;
        }
    };

    auto pickSecondFrom = [&](std::span<const MicroReg> regs) {
        for (const auto reg : regs)
        {
            if (reg == outReg0 || isForbidden(reg))
                continue;

            outReg1 = reg;
            break;
        }
    };

    pickFrom(intPersistentRegs);
    if (!outReg0.isValid())
        pickFrom(intTransientRegs);
    if (!outReg0.isValid())
        pickFrom(intRegs);

    if (!outReg0.isValid())
        return false;

    pickSecondFrom(intPersistentRegs);
    if (!outReg1.isValid())
        pickSecondFrom(intTransientRegs);
    if (!outReg1.isValid())
        pickSecondFrom(intRegs);

    if (!outReg1.isValid())
    {
        outReg0 = MicroReg::invalid();
        outReg1 = MicroReg::invalid();
        return false;
    }

    return true;
}

void CallConv::setup()
{
    setupCallConvWindowsX64(g_CallConvs[static_cast<size_t>(CallConvKind::WindowsX64)]);

    const auto hostCallConvKind                               = resolveHostCallConvKind();
    g_CallConvs[static_cast<size_t>(CallConvKind::Host)]      = g_CallConvs[static_cast<size_t>(hostCallConvKind)];
    g_CallConvs[static_cast<size_t>(CallConvKind::C)]         = g_CallConvs[static_cast<size_t>(hostCallConvKind)];
    g_CallConvs[static_cast<size_t>(CallConvKind::Host)].name = "host";
    g_CallConvs[static_cast<size_t>(CallConvKind::C)].name    = "c";
}

const CallConv& CallConv::get(CallConvKind kind)
{
    const size_t index = static_cast<size_t>(kind);
    SWC_ASSERT(index < K_CALL_CONV_COUNT);
    return g_CallConvs[index];
}

const CallConv& CallConv::host()
{
    return get(CallConvKind::Host);
}

SWC_END_NAMESPACE();

