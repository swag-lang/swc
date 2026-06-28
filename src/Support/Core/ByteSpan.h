#pragma once
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

using ByteSpanR  = std::span<const std::byte>;
using ByteSpanRW = std::span<std::byte>;
using ByteSpan   = ByteSpanR;

inline ByteSpanR asByteSpan(std::string_view v) noexcept
{
    return {reinterpret_cast<const std::byte*>(v.data()), v.size()};
}

inline ByteSpanRW asByteSpan(std::vector<std::byte>& v) noexcept
{
    return {v.data(), v.size()};
}

inline ByteSpanR asByteSpan(const std::vector<std::byte>& v) noexcept
{
    return {v.data(), v.size()};
}

inline ByteSpanRW asByteSpan(std::byte* data, size_t size) noexcept
{
    return {data, size};
}

inline ByteSpanR asByteSpan(const std::byte* data, size_t size) noexcept
{
    return {data, size};
}

inline ByteSpanR asByteSpan(ByteSpanRW v) noexcept
{
    return {v.data(), v.size()};
}

inline bool allZeroBytes(ByteSpanR v) noexcept
{
    for (const std::byte value : v)
    {
        if (value != std::byte{})
            return false;
    }

    return true;
}

inline bool byteSpanEq(ByteSpan lhs, ByteSpan rhs) noexcept
{
    return lhs.size() == rhs.size() && std::equal(lhs.begin(), lhs.end(), rhs.begin());
}

inline bool containsByte(ByteSpan bytes, std::byte value) noexcept
{
    return std::ranges::find(bytes, value) != bytes.end();
}

inline bool containsBytes(ByteSpan bytes, ByteSpan needle) noexcept
{
    if (needle.empty())
        return true;
    if (needle.size() > bytes.size())
        return false;
    return std::ranges::search(bytes, needle).begin() != bytes.end();
}

inline bool containsUtf16Le(ByteSpan bytes, std::string_view text) noexcept
{
    if (text.empty())
        return true;
    if (text.size() > bytes.size() / sizeof(char16_t))
        return false;

    const size_t needleSize = text.size() * sizeof(char16_t);
    for (size_t offset = 0; offset <= bytes.size() - needleSize; ++offset)
    {
        bool found = true;
        for (size_t i = 0; i < text.size(); ++i)
        {
            if (bytes[offset + i * 2] != static_cast<std::byte>(static_cast<uint8_t>(text[i])) || bytes[offset + i * 2 + 1] != std::byte{0})
            {
                found = false;
                break;
            }
        }
        if (found)
            return true;
    }
    return false;
}

inline bool containsRange(ByteSpan bytes, size_t offset, size_t size) noexcept
{
    return offset <= bytes.size() && size <= bytes.size() - offset;
}

template<typename T>
bool tryReadValue(T& outValue, ByteSpan bytes, size_t offset) noexcept
{
    static_assert(std::is_trivially_copyable_v<T>);
    if (!containsRange(bytes, offset, sizeof(T)))
        return false;

    std::memcpy(&outValue, bytes.data() + offset, sizeof(T));
    return true;
}

inline uint16_t readLe16(ByteSpan bytes, size_t offset) noexcept
{
    SWC_ASSERT(containsRange(bytes, offset, sizeof(uint16_t)));
    const auto* data = reinterpret_cast<const uint8_t*>(bytes.data() + offset);
    return static_cast<uint16_t>(data[0]) | (static_cast<uint16_t>(data[1]) << 8);
}

inline uint32_t readLe32(ByteSpan bytes, size_t offset) noexcept
{
    SWC_ASSERT(containsRange(bytes, offset, sizeof(uint32_t)));
    const auto* data = reinterpret_cast<const uint8_t*>(bytes.data() + offset);
    return static_cast<uint32_t>(data[0]) | (static_cast<uint32_t>(data[1]) << 8) | (static_cast<uint32_t>(data[2]) << 16) | (static_cast<uint32_t>(data[3]) << 24);
}

inline uint64_t readLe64(ByteSpan bytes, size_t offset) noexcept
{
    SWC_ASSERT(containsRange(bytes, offset, sizeof(uint64_t)));
    const auto* data  = reinterpret_cast<const uint8_t*>(bytes.data() + offset);
    uint64_t    value = 0;
    for (uint32_t i = 0; i < sizeof(uint64_t); ++i)
        value |= static_cast<uint64_t>(data[i]) << (i * 8);
    return value;
}

inline uint32_t readBe32(ByteSpan bytes, size_t offset) noexcept
{
    SWC_ASSERT(containsRange(bytes, offset, sizeof(uint32_t)));
    const auto* data = reinterpret_cast<const uint8_t*>(bytes.data() + offset);
    return (static_cast<uint32_t>(data[0]) << 24) | (static_cast<uint32_t>(data[1]) << 16) | (static_cast<uint32_t>(data[2]) << 8) | static_cast<uint32_t>(data[3]);
}

inline std::string_view asStringView(ByteSpanR v) noexcept
{
    return {reinterpret_cast<const char*>(v.data()), v.size()};
}

SWC_END_NAMESPACE();
