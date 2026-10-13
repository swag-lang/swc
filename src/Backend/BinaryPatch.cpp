#include "pch.h"
#include "Backend/BinaryPatch.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    template<typename T>
    T readScalar(std::span<const std::byte> bytes, size_t offset)
    {
        SWC_ASSERT(offset + sizeof(T) <= bytes.size());
        T value = 0;
        std::memcpy(&value, bytes.data() + offset, sizeof(value));
        return value;
    }
}

uint16_t BinaryPatch::readU16(std::span<const std::byte> bytes, size_t offset)
{
    return readScalar<uint16_t>(bytes, offset);
}

uint32_t BinaryPatch::readU32(std::span<const std::byte> bytes, size_t offset)
{
    return readScalar<uint32_t>(bytes, offset);
}

SWC_END_NAMESPACE();
