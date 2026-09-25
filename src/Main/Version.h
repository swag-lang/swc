#pragma once

// The compiler's identity, and part of the key of every cache it fills. Keep the build number
// stable during ordinary compiler changes; isolate or clear affected caches when validating
// behavior against artifacts produced by an older binary.
inline constexpr uint32_t SWC_VERSION   = 0;
inline constexpr uint32_t SWC_REVISION  = 1;
inline constexpr uint32_t SWC_BUILD_NUM = 1164;
