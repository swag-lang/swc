#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Support/Core/SmallVector.h"

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

struct CallConv
{
    // Concrete ABI contract used by lowering, register allocation, and final encoding.
    std::string_view name = "?";

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
    StructArgPassingInfo    structArgPassing;
    StructReturnPassingInfo structReturnPassing;

    bool stackRedZone = false;

    uint32_t             numArgRegisterSlots() const;
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
