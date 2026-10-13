#pragma once
#include "Support/Core/ByteArray.h"
#include "Support/Report/Assert.h"
#include <cstdint>
#include <cstring>

SWC_BEGIN_NAMESPACE();

namespace BinaryPatch
{
    uint16_t readU16(std::span<const std::byte> bytes, size_t offset);
    uint32_t readU32(std::span<const std::byte> bytes, size_t offset);

    template<typename T>
    inline void write(ByteArray& bytes, uint32_t offset, T value)
    {
        SWC_ASSERT(offset + sizeof(value) <= bytes.size());
        std::memcpy(bytes.data() + offset, &value, sizeof(value));
    }
}

SWC_END_NAMESPACE();
