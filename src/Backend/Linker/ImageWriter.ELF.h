#pragma once
#include "Support/Core/ByteArray.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();
struct LinkJob;

// Resolves prepared ELF objects, indexed archives and shared-library imports and writes
// a complete x86-64 executable/shared object without invoking a host toolchain.
bool buildElfImage(ByteArray& outBytes, Utf8& outError, const LinkJob& job);

SWC_END_NAMESPACE();
