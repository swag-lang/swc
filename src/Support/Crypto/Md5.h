#pragma once
#include "Support/Core/ByteSpan.h"

SWC_BEGIN_NAMESPACE();

namespace Crypto
{
    // RFC 1321 MD5 digest of the given bytes. Used to stamp source-file checksums into PDB debug info so
    // debuggers/profilers can verify and locate the matching source.
    std::array<uint8_t, 16> md5(ByteSpan data);
}

SWC_END_NAMESPACE();
