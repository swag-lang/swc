#pragma once
#include "Support/Core/ByteArray.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

inline constexpr uint16_t K_COFF_REL_AMD64_ADDR64 = 0x0001;
inline constexpr uint8_t  K_COFF_SYM_CLASS_STATIC = 0x03;
inline constexpr size_t   K_COFF_SHORT_NAME_SIZE  = 8;

struct NativeSectionRelocation
{
    uint32_t offset = 0;
    Utf8     symbolName;
    uint64_t addend = 0;
    uint16_t type   = K_COFF_REL_AMD64_ADDR64;
};

struct NativeSectionData
{
    Utf8                                 name;
    ByteArray                            bytes;
    std::vector<NativeSectionRelocation> relocations;
    uint32_t                             characteristics = 0;
    bool                                 bss             = false;
    uint32_t                             bssSize         = 0;
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
