#pragma once
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

class ByteView
{
public:
    ByteView() = default;
    explicit ByteView(std::span<const std::byte> bytes) :
        bytes_(bytes)
    {
    }

    const std::byte*           data() const noexcept { return bytes_.data(); }
    size_t                     size() const noexcept { return bytes_.size(); }
    bool                       empty() const noexcept { return bytes_.empty(); }
    std::span<const std::byte> span() const noexcept { return bytes_; }
    bool                       containsRange(size_t offset, size_t count) const noexcept { return offset <= size() && count <= size() - offset; }
    uint16_t                   readLe16(size_t offset) const noexcept { return read<uint16_t, std::endian::little>(offset); }
    uint32_t                   readLe32(size_t offset) const noexcept { return read<uint32_t, std::endian::little>(offset); }
    uint64_t                   readLe64(size_t offset) const noexcept { return read<uint64_t, std::endian::little>(offset); }
    uint32_t                   readBe32(size_t offset) const noexcept { return read<uint32_t, std::endian::big>(offset); }

private:
    template<typename T, std::endian Order>
    T read(size_t offset) const noexcept
    {
        SWC_ASSERT(containsRange(offset, sizeof(T)));
        T value;
        std::memcpy(&value, data() + offset, sizeof(T));
        if constexpr (std::endian::native != Order)
            value = std::byteswap(value);
        return value;
    }

    std::span<const std::byte> bytes_;
};

SWC_END_NAMESPACE();
