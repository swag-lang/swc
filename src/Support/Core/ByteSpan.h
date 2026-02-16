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

inline std::string_view asStringView(ByteSpanR v) noexcept
{
    return {reinterpret_cast<const char*>(v.data()), v.size()};
}

SWC_END_NAMESPACE();
