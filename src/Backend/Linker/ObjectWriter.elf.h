#pragma once
#include "Backend/Linker/LinkImage.h"

SWC_BEGIN_NAMESPACE();

class Diagnostic;

// ELF64 little-endian x86-64 relocatable objects. Relocations keep their explicit
// addends in SHT_RELA; undefined symbols remain for the final Linux link.
bool buildElfObject(ByteArray& outBytes, Diagnostic& outDiag, const LinkImage& image);

// Deterministic GNU archive with a big-endian 32-bit symbol index and ELF object members.
// Archives beyond the 32-bit offset limit are rejected before output allocation.
bool buildElfStaticArchive(ByteArray& outBytes, Diagnostic& outDiag, const std::vector<LinkArchiveMember>& members);

// A cached leaf object must define its function and resolve every relocation internally.
// Reject malformed ELF, foreign targets and external symbols before skipping code generation.
bool isSelfContainedElfObject(std::span<const std::byte> object, std::string_view requiredSymbol);

SWC_END_NAMESPACE();
