#pragma once
#include "Support/Core/ByteSpan.h"
#include "Support/Report/Assert.h"
#include "Support/Core/ByteArray.h"

SWC_BEGIN_NAMESPACE();

namespace ByteUtils
{
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

    inline void appendBytes(ByteArray& out, ByteSpan bytes)
    {
        out.append(bytes);
    }

    inline void appendBytes(std::vector<std::byte>& out, ByteSpan bytes)
    {
        if (bytes.empty())
            return;
        out.insert(out.end(), bytes.begin(), bytes.end());
    }

    inline void appendString(ByteArray& out, std::string_view text)
    {
        out.append(text);
    }

    inline void appendString(std::vector<std::byte>& out, std::string_view text)
    {
        appendBytes(out, asByteSpan(text));
    }

    inline void appendCString(ByteArray& out, std::string_view text)
    {
        out.appendCString(text);
    }

    inline void appendCString(std::vector<std::byte>& out, std::string_view text)
    {
        appendString(out, text);
        out.push_back(std::byte{0});
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

    inline void writeLe32(ByteSpanRW bytes, size_t offset, uint32_t value) noexcept
    {
        SWC_ASSERT(containsRange(asByteSpan(bytes), offset, sizeof(uint32_t)));
        for (uint32_t i = 0; i < sizeof(uint32_t); ++i)
            bytes[offset + i] = static_cast<std::byte>((value >> (i * 8)) & 0xFF);
    }

    inline void writeLe32(ByteArray& bytes, size_t offset, uint32_t value) noexcept
    {
        writeLe32(bytes.span(), offset, value);
    }

    inline void writeLe32(std::vector<std::byte>& bytes, size_t offset, uint32_t value) noexcept
    {
        writeLe32(asByteSpan(bytes), offset, value);
    }

    inline void writeLe64(ByteSpanRW bytes, size_t offset, uint64_t value) noexcept
    {
        SWC_ASSERT(containsRange(asByteSpan(bytes), offset, sizeof(uint64_t)));
        for (uint32_t i = 0; i < sizeof(uint64_t); ++i)
            bytes[offset + i] = static_cast<std::byte>((value >> (i * 8)) & 0xFF);
    }

    inline void writeLe64(ByteArray& bytes, size_t offset, uint64_t value) noexcept
    {
        writeLe64(bytes.span(), offset, value);
    }

    inline void writeLe64(std::vector<std::byte>& bytes, size_t offset, uint64_t value) noexcept
    {
        writeLe64(asByteSpan(bytes), offset, value);
    }

    inline void appendLe16(ByteArray& out, uint16_t value)
    {
        out.appendLe16(value);
    }

    inline void appendLe16(std::vector<std::byte>& out, uint16_t value)
    {
        out.push_back(static_cast<std::byte>(value & 0xFF));
        out.push_back(static_cast<std::byte>((value >> 8) & 0xFF));
    }

    inline void appendLe32(ByteArray& out, uint32_t value)
    {
        out.appendLe32(value);
    }

    inline void appendLe32(std::vector<std::byte>& out, uint32_t value)
    {
        for (uint32_t i = 0; i < sizeof(uint32_t); ++i)
            out.push_back(static_cast<std::byte>((value >> (i * 8)) & 0xFF));
    }

    inline uint32_t readBe32(ByteSpan bytes, size_t offset) noexcept
    {
        SWC_ASSERT(containsRange(bytes, offset, sizeof(uint32_t)));
        const auto* data = reinterpret_cast<const uint8_t*>(bytes.data() + offset);
        return (static_cast<uint32_t>(data[0]) << 24) | (static_cast<uint32_t>(data[1]) << 16) | (static_cast<uint32_t>(data[2]) << 8) | static_cast<uint32_t>(data[3]);
    }

    inline void appendBe32(ByteArray& out, uint32_t value)
    {
        out.appendBe32(value);
    }

    inline void appendBe32(std::vector<std::byte>& out, uint32_t value)
    {
        out.push_back(static_cast<std::byte>((value >> 24) & 0xFF));
        out.push_back(static_cast<std::byte>((value >> 16) & 0xFF));
        out.push_back(static_cast<std::byte>((value >> 8) & 0xFF));
        out.push_back(static_cast<std::byte>(value & 0xFF));
    }
}

SWC_END_NAMESPACE();
