#pragma once
#include "Support/Core/ByteArray.h"

SWC_BEGIN_NAMESPACE();

namespace Dwarf
{
    template<typename T>
    inline void appendUnsignedLeb128(ByteArray& bytes, T value)
    {
        do
        {
            const uint8_t part = value & 0x7f;
            value >>= 7;
            bytes.pushBack(std::byte{static_cast<uint8_t>(part | (value ? 0x80 : 0))});
        } while (value);
    }
}

SWC_END_NAMESPACE();
