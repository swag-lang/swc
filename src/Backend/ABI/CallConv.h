#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

enum class CallConvKind : uint8_t
{
    C,
    WindowsX64,
    Host,
};

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
    bool                 tryPickIntScratchRegs(MicroReg& outReg0, MicroReg& outReg1, std::span<const MicroReg> forbidden = {}) const;

    static void            setup();
    static const CallConv& get(CallConvKind kind);
    static const CallConv& host();
};

SWC_END_NAMESPACE();
