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

struct ByteArray : std::vector<std::byte>
{
    using Base = std::vector<std::byte>;

    using Base::Base;
    using Base::operator=;

    ByteArray() = default;

    ByteArray(Base bytes) :
        Base(std::move(bytes))
    {
    }

    ByteSpanRW span() noexcept { return {data(), size()}; }
    ByteSpan   span() const noexcept { return {data(), size()}; }

    bool allZero() const noexcept { return allZeroBytes(span()); }
    bool contains(const std::byte value) const noexcept { return containsByte(span(), value); }
    bool contains(const ByteSpan needle) const noexcept { return containsBytes(span(), needle); }
    bool contains(const std::string_view text) const noexcept { return contains(asByteSpan(text)); }

    void append(const ByteSpan bytes)
    {
        if (bytes.empty())
            return;
        insert(end(), bytes.begin(), bytes.end());
    }

    void append(const std::string_view text)
    {
        append(asByteSpan(text));
    }

    void appendCString(const std::string_view text)
    {
        append(text);
        push_back(std::byte{0});
    }

    void appendLe16(const uint16_t value)
    {
        push_back(static_cast<std::byte>(value & 0xFF));
        push_back(static_cast<std::byte>((value >> 8) & 0xFF));
    }

    void appendLe32(const uint32_t value)
    {
        for (uint32_t i = 0; i < sizeof(uint32_t); ++i)
            push_back(static_cast<std::byte>((value >> (i * 8)) & 0xFF));
    }

    void appendLe64(const uint64_t value)
    {
        for (uint32_t i = 0; i < sizeof(uint64_t); ++i)
            push_back(static_cast<std::byte>((value >> (i * 8)) & 0xFF));
    }

    void appendBe32(const uint32_t value)
    {
        push_back(static_cast<std::byte>((value >> 24) & 0xFF));
        push_back(static_cast<std::byte>((value >> 16) & 0xFF));
        push_back(static_cast<std::byte>((value >> 8) & 0xFF));
        push_back(static_cast<std::byte>(value & 0xFF));
    }

    void appendUtf16Le(const std::string_view text)
    {
        for (const char ch : text)
            appendLe16(static_cast<uint8_t>(ch));
    }

    void appendUtf16Le(const std::u16string_view text)
    {
        for (const char16_t ch : text)
            appendLe16(static_cast<uint16_t>(ch));
    }

    void appendUtf16LeZ(const std::u16string_view text)
    {
        appendUtf16Le(text);
        appendLe16(0);
    }

    void align(const size_t alignment, const std::byte pad = std::byte{0})
    {
        while (size() % alignment != 0)
            push_back(pad);
    }
};

inline ByteSpanRW asByteSpan(ByteArray& v) noexcept
{
    return v.span();
}

inline ByteSpan asByteSpan(const ByteArray& v) noexcept
{
    return v.span();
}

inline bool containsUtf16Le(ByteSpan bytes, std::string_view text)
{
    ByteArray needle;
    needle.reserve(text.size() * sizeof(char16_t));
    needle.appendUtf16Le(text);

    return containsBytes(bytes, needle.span());
}

inline std::string_view asStringView(ByteSpanR v) noexcept
{
    return {reinterpret_cast<const char*>(v.data()), v.size()};
}

SWC_END_NAMESPACE();
