#pragma once
#include "Support/Core/ByteSpan.h"

SWC_BEGIN_NAMESPACE();

namespace Crypto
{
    // FIPS 180-4 SHA-256 digest of the given bytes. Used to stamp source-file checksums into PDB debug
    // info (CodeView checksum kind 3) so debuggers/profilers can verify and locate the matching source.
    // This is the kind modern toolchains (and recent Visual Studio) expect; MD5 is deprecated.
    std::array<uint8_t, 32> sha256(ByteSpan data);
}

SWC_END_NAMESPACE();
