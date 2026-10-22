#pragma once

SWC_BEGIN_NAMESPACE();

// Constant references and native relocations share this partition of the 32-bit index.
namespace ConstantStorageLayout
{
    inline constexpr uint32_t SHARD_BITS  = 4;
    inline constexpr uint32_t SHARD_COUNT = 1u << SHARD_BITS;
    inline constexpr uint32_t LOCAL_BITS  = 32 - SHARD_BITS;
    inline constexpr uint32_t LOCAL_MASK  = (1u << LOCAL_BITS) - 1;
}

SWC_END_NAMESPACE();
