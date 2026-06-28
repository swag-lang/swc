#include "pch.h"
#include "Support/Core/ByteArray.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

ByteArray::ByteArray(Base bytes) :
    Base(std::move(bytes))
{
}

std::span<std::byte> ByteArray::span() noexcept
{
    return {data(), size()};
}

std::span<const std::byte> ByteArray::span() const noexcept
{
    return {data(), size()};
}

bool ByteArray::allZero() const noexcept
{
    for (const std::byte value : *this)
    {
        if (value != std::byte{})
            return false;
    }
    return true;
}

bool ByteArray::contains(const std::byte value) const noexcept
{
    return std::ranges::find(*this, value) != end();
}

bool ByteArray::contains(const std::span<const std::byte> needle) const noexcept
{
    if (needle.empty())
        return true;
    if (needle.size() > size())
        return false;
    const std::span<const std::byte> bytes = span();
    return std::ranges::search(bytes, needle).begin() != bytes.end();
}

bool ByteArray::contains(const ByteArray& needle) const noexcept
{
    return contains(needle.span());
}

bool ByteArray::contains(const std::string_view text) const noexcept
{
    return contains(std::span<const std::byte>{reinterpret_cast<const std::byte*>(text.data()), text.size()});
}

bool ByteArray::containsUtf16Le(const std::string_view text) const noexcept
{
    if (text.empty())
        return true;
    if (text.size() > size() / sizeof(char16_t))
        return false;

    const size_t needleSize = text.size() * sizeof(char16_t);
    for (size_t offset = 0; offset <= size() - needleSize; ++offset)
    {
        bool found = true;
        for (size_t i = 0; i < text.size(); ++i)
        {
            if ((*this)[offset + i * 2] != static_cast<std::byte>(static_cast<uint8_t>(text[i])) || (*this)[offset + i * 2 + 1] != std::byte{0})
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

bool ByteArray::containsRange(const size_t offset, const size_t byteCount) const noexcept
{
    return offset <= size() && byteCount <= size() - offset;
}

uint16_t ByteArray::readLe16(const size_t offset) const noexcept
{
    SWC_ASSERT(containsRange(offset, sizeof(uint16_t)));
    return std::to_integer<uint16_t>((*this)[offset + 0]) | (std::to_integer<uint16_t>((*this)[offset + 1]) << 8);
}

uint32_t ByteArray::readLe32(const size_t offset) const noexcept
{
    SWC_ASSERT(containsRange(offset, sizeof(uint32_t)));
    uint32_t value = 0;
    for (uint32_t i = 0; i < sizeof(uint32_t); ++i)
        value |= std::to_integer<uint32_t>((*this)[offset + i]) << (i * 8);
    return value;
}

uint64_t ByteArray::readLe64(const size_t offset) const noexcept
{
    SWC_ASSERT(containsRange(offset, sizeof(uint64_t)));
    uint64_t value = 0;
    for (uint32_t i = 0; i < sizeof(uint64_t); ++i)
        value |= std::to_integer<uint64_t>((*this)[offset + i]) << (i * 8);
    return value;
}

uint32_t ByteArray::readBe32(const size_t offset) const noexcept
{
    SWC_ASSERT(containsRange(offset, sizeof(uint32_t)));
    return (std::to_integer<uint32_t>((*this)[offset + 0]) << 24) | (std::to_integer<uint32_t>((*this)[offset + 1]) << 16) | (std::to_integer<uint32_t>((*this)[offset + 2]) << 8) | std::to_integer<uint32_t>((*this)[offset + 3]);
}

void ByteArray::append(const std::span<const std::byte> bytes)
{
    if (bytes.empty())
        return;
    insert(end(), bytes.begin(), bytes.end());
}

void ByteArray::append(const ByteArray& bytes)
{
    append(bytes.span());
}

void ByteArray::append(const std::string_view text)
{
    append(std::span<const std::byte>{reinterpret_cast<const std::byte*>(text.data()), text.size()});
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

void ByteArray::writeLe16(const size_t offset, const uint16_t value) noexcept
{
    SWC_ASSERT(containsRange(offset, sizeof(uint16_t)));
    (*this)[offset + 0] = static_cast<std::byte>(value & 0xFF);
    (*this)[offset + 1] = static_cast<std::byte>((value >> 8) & 0xFF);
}

void ByteArray::writeLe32(const size_t offset, const uint32_t value) noexcept
{
    SWC_ASSERT(containsRange(offset, sizeof(uint32_t)));
    for (uint32_t i = 0; i < sizeof(uint32_t); ++i)
        (*this)[offset + i] = static_cast<std::byte>((value >> (i * 8)) & 0xFF);
}

void ByteArray::writeLe64(const size_t offset, const uint64_t value) noexcept
{
    SWC_ASSERT(containsRange(offset, sizeof(uint64_t)));
    for (uint32_t i = 0; i < sizeof(uint64_t); ++i)
        (*this)[offset + i] = static_cast<std::byte>((value >> (i * 8)) & 0xFF);
}

void ByteArray::align(const size_t alignment, const std::byte pad)
{
    while (size() % alignment != 0)
        push_back(pad);
}

SWC_END_NAMESPACE();
