#pragma once
#include "Backend/Linker/LinkImage.h"

SWC_BEGIN_NAMESPACE();

class Diagnostic;

// Serialises a resolved LinkImage into a Windows PE32+ image (executable or DLL). All symbol
// resolution, section layout, relocation patching, import-table/IAT synthesis and base-relocation
// generation happen here; the result is the exact bytes to write to disk. Returns false and fills
// outDiag on an unresolved symbol or a structural problem.
bool writePeImage(std::vector<std::byte>& outBytes, Diagnostic& outDiag, const LinkImage& image);

SWC_END_NAMESPACE();
