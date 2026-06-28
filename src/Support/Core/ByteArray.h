#pragma once

SWC_BEGIN_NAMESPACE();

struct ByteArray : std::vector<std::byte>
{
    using Base = std::vector<std::byte>;

    using Base::Base;
    using Base::operator=;

    ByteArray() = default;
    ByteArray(Base bytes);

    std::span<std::byte>       span() noexcept;
    std::span<const std::byte> span() const noexcept;

    bool allZero() const noexcept;
    bool contains(std::byte value) const noexcept;
    bool contains(std::span<const std::byte> needle) const noexcept;
    bool contains(const ByteArray& needle) const noexcept;
    bool contains(std::string_view text) const noexcept;
    bool containsUtf16Le(std::string_view text) const noexcept;
    bool containsRange(size_t offset, size_t byteCount) const noexcept;

    uint16_t readLe16(size_t offset) const noexcept;
    uint32_t readLe32(size_t offset) const noexcept;
    uint64_t readLe64(size_t offset) const noexcept;
    uint32_t readBe32(size_t offset) const noexcept;

    void append(std::span<const std::byte> bytes);
    void append(const ByteArray& bytes);
    void append(std::string_view text);
    void appendCString(std::string_view text);
    void appendLe16(uint16_t value);
    void appendLe32(uint32_t value);
    void appendLe64(uint64_t value);
    void appendBe32(uint32_t value);
    void appendUtf16Le(std::string_view text);
    void appendUtf16Le(std::u16string_view text);
    void appendUtf16LeZ(std::u16string_view text);
    void writeLe16(size_t offset, uint16_t value) noexcept;
    void writeLe32(size_t offset, uint32_t value) noexcept;
    void writeLe64(size_t offset, uint64_t value) noexcept;
    void align(size_t alignment, std::byte pad = std::byte{0});
};

SWC_END_NAMESPACE();
