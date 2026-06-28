#include "pch.h"
#include "Support/Core/ByteArray.h"

SWC_BEGIN_NAMESPACE();

ByteArray::ByteArray(Base bytes) :
    Base(std::move(bytes))
{
}

ByteSpanRW ByteArray::span() noexcept
{
    return {data(), size()};
}

ByteSpan ByteArray::span() const noexcept
{
    return {data(), size()};
}

bool ByteArray::allZero() const noexcept
{
    return allZeroBytes(span());
}

bool ByteArray::contains(const std::byte value) const noexcept
{
    return containsByte(span(), value);
}

bool ByteArray::contains(const ByteSpan needle) const noexcept
{
    return containsBytes(span(), needle);
}

bool ByteArray::contains(const std::string_view text) const noexcept
{
    return contains(asByteSpan(text));
}

void ByteArray::append(const ByteSpan bytes)
{
    if (bytes.empty())
        return;
    insert(end(), bytes.begin(), bytes.end());
}

void ByteArray::append(const std::string_view text)
{
    append(asByteSpan(text));
}

void ByteArray::appendCString(const std::string_view text)
{
    append(text);
    push_back(std::byte{0});
}

void ByteArray::appendLe16(const uint16_t value)
{
    push_back(static_cast<std::byte>(value & 0xFF));
    push_back(static_cast<std::byte>((value >> 8) & 0xFF));
}

void ByteArray::appendLe32(const uint32_t value)
{
    for (uint32_t i = 0; i < sizeof(uint32_t); ++i)
        push_back(static_cast<std::byte>((value >> (i * 8)) & 0xFF));
}

void ByteArray::appendLe64(const uint64_t value)
{
    for (uint32_t i = 0; i < sizeof(uint64_t); ++i)
        push_back(static_cast<std::byte>((value >> (i * 8)) & 0xFF));
}

void ByteArray::appendBe32(const uint32_t value)
{
    push_back(static_cast<std::byte>((value >> 24) & 0xFF));
    push_back(static_cast<std::byte>((value >> 16) & 0xFF));
    push_back(static_cast<std::byte>((value >> 8) & 0xFF));
    push_back(static_cast<std::byte>(value & 0xFF));
}

void ByteArray::appendUtf16Le(const std::string_view text)
{
    for (const char ch : text)
        appendLe16(static_cast<uint8_t>(ch));
}

void ByteArray::appendUtf16Le(const std::u16string_view text)
{
    for (const char16_t ch : text)
        appendLe16(static_cast<uint16_t>(ch));
}

void ByteArray::appendUtf16LeZ(const std::u16string_view text)
{
    appendUtf16Le(text);
    appendLe16(0);
}

void ByteArray::align(const size_t alignment, const std::byte pad)
{
    while (size() % alignment != 0)
        push_back(pad);
}

ByteSpanRW asByteSpan(ByteArray& v) noexcept
{
    return v.span();
}

ByteSpan asByteSpan(const ByteArray& v) noexcept
{
    return v.span();
}

bool containsUtf16Le(const ByteSpan bytes, const std::string_view text)
{
    ByteArray needle;
    needle.reserve(text.size() * sizeof(char16_t));
    needle.appendUtf16Le(text);

    return containsBytes(bytes, needle.span());
}

SWC_END_NAMESPACE();
