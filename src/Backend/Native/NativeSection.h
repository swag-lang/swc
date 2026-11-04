#pragma once
#include "Support/Core/ByteArray.h"
#include "Support/Core/Utf8.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

inline constexpr uint8_t K_COFF_SYM_CLASS_STATIC = 0x03;
inline constexpr size_t  K_COFF_SHORT_NAME_SIZE  = 8;

enum class NativeRelocationKind : uint8_t
{
    Abs64,
    Rva32,
    Rel32,
    SectionOffset32,
    SectionIndex16,
    GotRel32,
};

struct NativeSectionRelocation
{
    uint32_t             offset = 0;
    Utf8                 symbolName;
    uint64_t             addend = 0;
    NativeRelocationKind kind   = NativeRelocationKind::Abs64;
};

struct NativeSectionData
{
    Utf8                                 name;
    ByteArray                            bytes;
    std::vector<NativeSectionRelocation> relocations;
    uint32_t                             characteristics = 0;
    bool                                 bss             = false;
    uint32_t                             bssSize         = 0;

    // Storage offsets and the section base must both satisfy every contained allocation.
    void requireAlignment(const uint32_t alignment)
    {
        SWC_ASSERT(std::has_single_bit(alignment));
        constexpr uint32_t K_ALIGNMENT_MASK = 0x00F00000u;
        const uint32_t     flags            = (std::countr_zero(std::min(alignment, 8192u)) + 1) << 20;
        characteristics                     = (characteristics & ~K_ALIGNMENT_MASK) | std::max(characteristics & K_ALIGNMENT_MASK, flags);
    }
};

struct NativeCodeRelocationTarget
{
    ByteArray*                            bytes                  = nullptr;
    std::vector<NativeSectionRelocation>* relocations            = nullptr;
    uint32_t                              functionOffset         = 0;
    bool                                  allowUnresolvedSymbols = false;
    bool                                  splitRDataReferences   = false;
};

SWC_END_NAMESPACE();
