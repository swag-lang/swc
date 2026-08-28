#pragma once

// The compiler's identity, and part of the key of every cache it fills. A build produced by one
// version is never read back by another: bump SWC_BUILD_NUM with every change to the compiler,
// so what the previous one left behind is ignored instead of trusted.
inline constexpr uint32_t SWC_VERSION   = 0;
inline constexpr uint32_t SWC_REVISION  = 1;
inline constexpr uint32_t SWC_BUILD_NUM = 251;
