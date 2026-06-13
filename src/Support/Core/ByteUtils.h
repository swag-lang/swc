#pragma once
#include "Support/Core/ByteSpan.h"

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

    inline void appendBytes(std::vector<std::byte>& out, ByteSpan bytes)
    {
        if (bytes.empty())
            return;
        out.insert(out.end(), bytes.begin(), bytes.end());
    }

    inline void appendString(std::vector<std::byte>& out, std::string_view text)
    {
        appendBytes(out, asByteSpan(text));
    }

    inline void appendCString(std::vector<std::byte>& out, std::string_view text)
    {
        appendString(out, text);
        out.push_back(std::byte{0});
    }

    inline uint16_t readLE16(ByteSpan bytes, size_t offset) noexcept
    {
        SWC_ASSERT(containsRange(bytes, offset, sizeof(uint16_t)));
        const auto* data = reinterpret_cast<const uint8_t*>(bytes.data() + offset);
        return static_cast<uint16_t>(data[0]) | (static_cast<uint16_t>(data[1]) << 8);
    }

    inline uint32_t readLE32(ByteSpan bytes, size_t offset) noexcept
    {
        SWC_ASSERT(containsRange(bytes, offset, sizeof(uint32_t)));
        const auto* data = reinterpret_cast<const uint8_t*>(bytes.data() + offset);
        return static_cast<uint32_t>(data[0]) | (static_cast<uint32_t>(data[1]) << 8) | (static_cast<uint32_t>(data[2]) << 16) | (static_cast<uint32_t>(data[3]) << 24);
    }

    inline uint64_t readLE64(ByteSpan bytes, size_t offset) noexcept
    {
        SWC_ASSERT(containsRange(bytes, offset, sizeof(uint64_t)));
        const auto* data  = reinterpret_cast<const uint8_t*>(bytes.data() + offset);
        uint64_t    value = 0;
        for (uint32_t i = 0; i < sizeof(uint64_t); ++i)
            value |= static_cast<uint64_t>(data[i]) << (i * 8);
        return value;
    }

    inline void writeLE32(ByteSpanRW bytes, size_t offset, uint32_t value) noexcept
    {
        SWC_ASSERT(containsRange(asByteSpan(bytes), offset, sizeof(uint32_t)));
        for (uint32_t i = 0; i < sizeof(uint32_t); ++i)
            bytes[offset + i] = static_cast<std::byte>((value >> (i * 8)) & 0xFF);
    }

    inline void writeLE32(std::vector<std::byte>& bytes, size_t offset, uint32_t value) noexcept
    {
        writeLE32(asByteSpan(bytes), offset, value);
    }

    inline void writeLE64(ByteSpanRW bytes, size_t offset, uint64_t value) noexcept
    {
        SWC_ASSERT(containsRange(asByteSpan(bytes), offset, sizeof(uint64_t)));
        for (uint32_t i = 0; i < sizeof(uint64_t); ++i)
            bytes[offset + i] = static_cast<std::byte>((value >> (i * 8)) & 0xFF);
    }

    inline void writeLE64(std::vector<std::byte>& bytes, size_t offset, uint64_t value) noexcept
    {
        writeLE64(asByteSpan(bytes), offset, value);
    }

    inline void appendLE16(std::vector<std::byte>& out, uint16_t value)
    {
        out.push_back(static_cast<std::byte>(value & 0xFF));
        out.push_back(static_cast<std::byte>((value >> 8) & 0xFF));
    }

    inline void appendLE32(std::vector<std::byte>& out, uint32_t value)
    {
        for (uint32_t i = 0; i < sizeof(uint32_t); ++i)
            out.push_back(static_cast<std::byte>((value >> (i * 8)) & 0xFF));
    }

    inline uint32_t readBE32(ByteSpan bytes, size_t offset) noexcept
    {
        SWC_ASSERT(containsRange(bytes, offset, sizeof(uint32_t)));
        const auto* data = reinterpret_cast<const uint8_t*>(bytes.data() + offset);
        return (static_cast<uint32_t>(data[0]) << 24) | (static_cast<uint32_t>(data[1]) << 16) | (static_cast<uint32_t>(data[2]) << 8) | static_cast<uint32_t>(data[3]);
    }

    inline void appendBE32(std::vector<std::byte>& out, uint32_t value)
    {
        out.push_back(static_cast<std::byte>((value >> 24) & 0xFF));
        out.push_back(static_cast<std::byte>((value >> 16) & 0xFF));
        out.push_back(static_cast<std::byte>((value >> 8) & 0xFF));
        out.push_back(static_cast<std::byte>(value & 0xFF));
    }
}

SWC_END_NAMESPACE();
