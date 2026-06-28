#pragma once
#include "Backend/Linker/LinkImage.h"

SWC_BEGIN_NAMESPACE();

class Diagnostic;

struct Win32ResourceRvaPatch
{
    uint32_t dataEntryOffset = 0;
    uint32_t payloadOffset   = 0;
};

struct Win32ResourceSection
{
    ByteArray                          bytes;
    std::vector<Win32ResourceRvaPatch> rvaPatches;
};

class Win32OsPatcher final
{
public:
    static bool buildResourceSection(Win32ResourceSection& outSection, Diagnostic& outDiag, const LinkImage& image);
    static void patchResourceSectionRvas(ByteArray& bytes, std::span<const Win32ResourceRvaPatch> patches, uint32_t sectionRva);
};

SWC_END_NAMESPACE();
