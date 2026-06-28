#include "pch.h"
#include "Support/Core/ByteArray.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

ByteArray::ByteArray(const std::initializer_list<std::byte> bytes) :
    storage_(bytes)
{
}

ByteArray::ByteArray(const size_t count) :
    storage_(count)
{
}

ByteArray::ByteArray(const size_t count, const std::byte value) :
    storage_(count, value)
{
}

ByteArray::ByteArray(Storage bytes) :
    storage_(std::move(bytes))
{
}

ByteArray& ByteArray::operator=(const std::initializer_list<std::byte> bytes)
{
    storage_ = bytes;
    return *this;
}

bool ByteArray::operator==(const ByteArray& other) const noexcept
{
    return storage_ == other.storage_;
}

bool ByteArray::operator!=(const ByteArray& other) const noexcept
{
    return storage_ != other.storage_;
}

ByteArray::iterator ByteArray::begin() noexcept
{
    return storage_.begin();
}

ByteArray::const_iterator ByteArray::begin() const noexcept
{
    return storage_.begin();
}

ByteArray::const_iterator ByteArray::cbegin() const noexcept
{
    return storage_.cbegin();
}

ByteArray::iterator ByteArray::end() noexcept
{
    return storage_.end();
}

ByteArray::const_iterator ByteArray::end() const noexcept
{
    return storage_.end();
}

ByteArray::const_iterator ByteArray::cend() const noexcept
{
    return storage_.cend();
}

std::byte* ByteArray::data() noexcept
{
    return storage_.data();
}

const std::byte* ByteArray::data() const noexcept
{
    return storage_.data();
}

size_t ByteArray::size() const noexcept
{
    return storage_.size();
}

bool ByteArray::empty() const noexcept
{
    return storage_.empty();
}

void ByteArray::clear() noexcept
{
    storage_.clear();
}

void ByteArray::reserve(const size_t count)
{
    storage_.reserve(count);
}

void ByteArray::resize(const size_t count)
{
    storage_.resize(count);
}

void ByteArray::resize(const size_t count, const std::byte value)
{
    storage_.resize(count, value);
}

void ByteArray::pushBack(const std::byte value)
{
    storage_.push_back(value);
}

std::byte& ByteArray::operator[](const size_t index) noexcept
{
    return storage_[index];
}

const std::byte& ByteArray::operator[](const size_t index) const noexcept
{
    return storage_[index];
}

ByteArray::iterator ByteArray::insert(const const_iterator pos, const size_t count, const std::byte value)
{
    return storage_.insert(pos, count, value);
}

void ByteArray::assign(const size_t count, const std::byte value)
{
    storage_.assign(count, value);
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
    for (const std::byte value : storage_)
    {
        if (value != std::byte{})
            return false;
    }
    return true;
}

bool ByteArray::contains(const std::byte value) const noexcept
{
    return std::ranges::find(storage_, value) != storage_.end();
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
    storage_.insert(storage_.end(), bytes.begin(), bytes.end());
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
    pushBack(std::byte{0});
}

void ByteArray::appendLe16(const uint16_t value)
{
    pushBack(static_cast<std::byte>(value & 0xFF));
    pushBack(static_cast<std::byte>((value >> 8) & 0xFF));
}

void ByteArray::appendLe32(const uint32_t value)
{
    for (uint32_t i = 0; i < sizeof(uint32_t); ++i)
        pushBack(static_cast<std::byte>((value >> (i * 8)) & 0xFF));
}

void ByteArray::appendLe64(const uint64_t value)
{
    for (uint32_t i = 0; i < sizeof(uint64_t); ++i)
        pushBack(static_cast<std::byte>((value >> (i * 8)) & 0xFF));
}

void ByteArray::appendBe32(const uint32_t value)
{
    pushBack(static_cast<std::byte>((value >> 24) & 0xFF));
    pushBack(static_cast<std::byte>((value >> 16) & 0xFF));
    pushBack(static_cast<std::byte>((value >> 8) & 0xFF));
    pushBack(static_cast<std::byte>(value & 0xFF));
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
        pushBack(pad);
}

SWC_END_NAMESPACE();
