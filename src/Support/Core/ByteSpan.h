#pragma once

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

bool containsUtf16Le(ByteSpan bytes, std::string_view text);

inline std::string_view asStringView(ByteSpanR v) noexcept
{
    return {reinterpret_cast<const char*>(v.data()), v.size()};
}

SWC_END_NAMESPACE();
