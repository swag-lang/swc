#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Support/Core/SmallVector.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

enum class CallConvKind : uint8_t
{
    // Target C ABI for the selected platform.
    C,
    // Concrete Windows x64 ABI.
    WindowsX64,
    // Swag's default compiled/JIT ABI for the current target runtime.
    Swag,
};

constexpr bool isValidCallConvKind(CallConvKind kind) noexcept
{
    switch (kind)
    {
        case CallConvKind::C:
        case CallConvKind::WindowsX64:
        case CallConvKind::Swag:
            return true;
    }

    return false;
}

enum class StructArgPassingKind : uint8_t
{
    ByValue,
    ByReference,
};

struct StructArgPassingInfo
{
    uint64_t passByValueSizeMask      = 0;
    bool     passByValueInIntSlots    = true;
    bool     passByReferenceNeedsCopy = true;
};

struct StructReturnPassingInfo
{
    uint64_t passByValueSizeMask = 0;
};

struct CallFloatArgs
{
    // Two bits per ABI register: absent, f32, f64, or full/unknown width.
    // Presence-only callers retain the conservative full-register contract.
    uint16_t widths = 0;

    constexpr CallFloatArgs(uint8_t presence = 0)
    {
        for (uint32_t index = 0; index < 8; ++index)
        {
            if (presence & (1u << index))
                widths |= static_cast<uint16_t>(3u << (index * 2));
        }
    }

    void setWidth(uint32_t index, uint8_t numBits)
    {
        SWC_ASSERT(index < 8 && (numBits == 32 || numBits == 64 || numBits == 128));
        const uint16_t width = numBits == 32 ? 1 : numBits == 64 ? 2
                                                                 : 3;
        widths               = static_cast<uint16_t>((widths & ~(3u << (index * 2))) | (width << (index * 2)));
    }

    uint8_t laneMask(uint32_t index) const
    {
        SWC_ASSERT(index < 8);
        constexpr uint8_t masks[] = {0, 1, 3, 15};
        return masks[(widths >> (index * 2)) & 3];
    }
};

struct CallConv
{
    // Concrete ABI contract used by lowering, register allocation, and final encoding.
    std::string_view name        = "?";
    std::string_view displayName = "?";

    MicroReg stackPointer;
    MicroReg framePointer;
    MicroReg intReturn;
    MicroReg floatReturn;

    SmallVector<MicroReg> intRegs;
    SmallVector<MicroReg> floatRegs;

    SmallVector<MicroReg> intArgRegs;
    SmallVector<MicroReg> floatArgRegs;

    SmallVector<MicroReg> intTransientRegs;
    SmallVector<MicroReg> intPersistentRegs;

    SmallVector<MicroReg> floatTransientRegs;
    SmallVector<MicroReg> floatPersistentRegs;

    // Stack layout fields are expressed in bytes.
    uint32_t                stackAlignment       = 0;
    uint32_t                stackParamAlignment  = 0;
    uint32_t                stackParamSlotSize   = 0;
    uint32_t                stackShadowSpace     = 0;
    uint32_t                argRegisterSlotCount = 0;
    bool                    independentArgBanks  = false;
    StructArgPassingInfo    structArgPassing;
    StructReturnPassingInfo structReturnPassing;

    bool stackRedZone = false;

    uint32_t             numArgRegisterSlots() const;
    bool                 canPassArgInRegister(uint32_t argIndex, bool isFloat) const;
    uint32_t             stackSlotSize() const;
    bool                 canPassStructArgByValue(uint32_t sizeInBytes) const;
    bool                 canPassStructReturnByValue(uint32_t sizeInBytes) const;
    StructArgPassingKind classifyStructArgPassing(uint32_t sizeInBytes) const;
    StructArgPassingKind classifyStructReturnPassing(uint32_t sizeInBytes) const;
    bool                 isIntArgReg(MicroReg reg) const;
    bool                 isIntPersistentReg(MicroReg reg) const;
    bool                 isFloatPersistentReg(MicroReg reg) const;
    MicroReg             preferredLocalStackBaseReg() const;
    bool                 tryPickIntScratchRegs(MicroReg& outReg0, MicroReg& outReg1, MicroRegSpan forbidden = {}) const;

    static void            setup();
    static const CallConv& get(CallConvKind kind);
    static const CallConv& swag();
};

SWC_END_NAMESPACE();
