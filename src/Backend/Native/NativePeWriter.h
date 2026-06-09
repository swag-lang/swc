#pragma once
#include "Backend/Native/NativeLinkImage.h"

SWC_BEGIN_NAMESPACE();

// Serialises a resolved LinkImage into a Windows PE32+ image (executable or DLL). All symbol
// resolution, section layout, relocation patching, import-table/IAT synthesis and base-relocation
// generation happen here; the result is the exact bytes to write to disk. Returns false and fills
// outError on an unresolved symbol or a structural problem.
bool writePeImage(const LinkImage& image, std::vector<std::byte>& outBytes, Utf8& outError);

SWC_END_NAMESPACE();
