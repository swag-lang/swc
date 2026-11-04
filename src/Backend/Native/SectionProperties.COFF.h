#pragma once

#include "Backend/Linker/Format.COFF.h"
#include "Backend/Linker/Reader.COFF.h"
#include "Backend/Native/NativeSection.h"

SWC_BEGIN_NAMESPACE();

inline constexpr uint32_t K_NATIVE_TEXT_SECTION_COFF_CHARACTERISTICS = PE::SCN_CNT_CODE | PE::SCN_MEM_EXECUTE | PE::SCN_MEM_READ | PE::SCN_ALIGN_32BYTES;

inline uint32_t applyNativeSectionCoffProperties(LinkSection& destination, const NativeSectionData& source)
{
    const uint32_t alignment = coffSectionAlignmentFromCharacteristics(source.characteristics);
    destination.align = std::max(destination.align, alignment);
    destination.flags.add(linkSectionFlagsFromCoffCharacteristics(source.characteristics));
    return alignment;
}

SWC_END_NAMESPACE();
