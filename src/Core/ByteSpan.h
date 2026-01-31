#pragma once

#include <cstddef>
#include <span>
#include <string_view>

SWC_BEGIN_NAMESPACE();

// A view of raw bytes.
// Note: use `std::as_bytes` / `asByteSpan` to create from other spans.
using ByteSpan = std::span<const std::byte>;

inline ByteSpan asByteSpan(std::string_view v) noexcept
{
    return {reinterpret_cast<const std::byte*>(v.data()), v.size()};
}

inline std::string_view asStringView(ByteSpan v) noexcept
{
    return {reinterpret_cast<const char*>(v.data()), v.size()};
}

SWC_END_NAMESPACE();
