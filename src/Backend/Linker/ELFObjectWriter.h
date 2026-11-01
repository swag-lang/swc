#pragma once
#include "Backend/Linker/LinkImage.h"

SWC_BEGIN_NAMESPACE();

class Diagnostic;

// ELF64 little-endian x86-64 relocatable objects. Relocations keep their explicit
// addends in SHT_RELA; undefined symbols remain for the final Linux link.
bool buildElfObject(ByteArray& outBytes, Diagnostic& outDiag, const LinkImage& image);

SWC_END_NAMESPACE();
