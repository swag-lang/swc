#pragma once

SWC_BEGIN_NAMESPACE();

struct ByteArray
{
    using Storage        = std::vector<std::byte>;
    using value_type     = Storage::value_type;
    using iterator       = Storage::iterator;
    using const_iterator = Storage::const_iterator;

    ByteArray()                                = default;
    ByteArray(const ByteArray&)                = default;
    ByteArray(ByteArray&&) noexcept            = default;
    ByteArray& operator=(const ByteArray&)     = default;
    ByteArray& operator=(ByteArray&&) noexcept = default;
    ByteArray(std::initializer_list<std::byte> bytes);
    explicit ByteArray(size_t count);
    ByteArray(size_t count, std::byte value);
    explicit ByteArray(Storage bytes);

    template<typename IT>
    ByteArray(IT first, IT last) :
        storage_(first, last)
    {
    }

    ByteArray& operator=(std::initializer_list<std::byte> bytes);
    bool       operator==(const ByteArray& other) const noexcept;
    bool       operator!=(const ByteArray& other) const noexcept;

    iterator       begin() noexcept;
    const_iterator begin() const noexcept;
    const_iterator cbegin() const noexcept;
    iterator       end() noexcept;
    const_iterator end() const noexcept;
    const_iterator cend() const noexcept;

    std::byte*       data() noexcept;
    const std::byte* data() const noexcept;
    size_t           size() const noexcept;
    bool             empty() const noexcept;
    void             clear() noexcept;
    void             reserve(size_t count);
    void             resize(size_t count);
    void             resize(size_t count, std::byte value);
    void             pushBack(std::byte value);
    std::byte&       operator[](size_t index) noexcept;
    const std::byte& operator[](size_t index) const noexcept;

    iterator insert(const_iterator pos, size_t count, std::byte value);
    void     assign(size_t count, std::byte value);

    template<typename IT>
    iterator insert(const_iterator pos, IT first, IT last)
    {
        return storage_.insert(pos, first, last);
    }

    template<typename IT>
    void assign(IT first, IT last)
    {
        storage_.assign(first, last);
    }

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

private:
    Storage storage_;
};

SWC_END_NAMESPACE();
