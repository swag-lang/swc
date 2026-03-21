#pragma once
#include "Support/Core/PagedStore.h"

SWC_BEGIN_NAMESPACE();

enum class DataSegmentKind : uint8_t
{
    Zero,
    GlobalZero,
    GlobalInit,
    Compiler,
};

struct DataSegmentRelocation
{
    uint32_t offset;
    uint32_t targetOffset;
};

struct DataSegmentAllocation
{
    uint32_t offset = 0;
    uint32_t size   = 0;
    uint32_t align  = 1;
};

class DataSegment
{
public:
    struct LargeBlock
    {
        uint32_t                     offset = 0;
        uint32_t                     size   = 0;
        std::unique_ptr<std::byte[]> storage;
    };

    std::pair<ByteSpan, Ref>                  addSpan(ByteSpan value);
    std::pair<ByteSpan, Ref>                  addSpan(ByteSpan value, uint32_t align);
    std::pair<std::string_view, Ref>          addString(const Utf8& value);
    uint32_t                                  addString(uint32_t baseOffset, uint32_t fieldOffset, const Utf8& value);
    void                                      addRelocation(uint32_t offset, uint32_t targetOffset);
    std::pair<uint32_t, std::byte*>           reserveBytes(uint32_t size, uint32_t align, bool zeroInit);
    uint32_t                                  reserveBlock(uint32_t size, uint32_t align, bool zeroInit);
    Ref                                       findRef(const void* ptr) const noexcept;
    bool                                      findAllocation(DataSegmentAllocation& outAllocation, uint32_t offset) const noexcept;
    uint32_t                                  size() const noexcept;
    uint32_t                                  extentSize() const noexcept;
    void                                      copyTo(ByteSpanRW dst) const;
    void                                      copyToPreserveOffsets(ByteSpanRW dst) const;
    void                                      restoreFromPreserveOffsets(ByteSpan src) const;
    const std::vector<DataSegmentRelocation>& relocations() const { return relocations_; }
#if SWC_HAS_STATS
    size_t memStorageReserved() const;
#endif

    template<typename T>
    std::pair<uint32_t, T*> reserve()
    {
        std::unique_lock lock(mutex_);
        const auto [offset, ptr] = allocateStorageLocked(static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)), true);
        return {offset, reinterpret_cast<T*>(ptr)};
    }

    template<typename T>
    std::pair<uint32_t, T*> reserveSpan(uint32_t count)
    {
        if (!count)
            return {INVALID_REF, nullptr};
        std::unique_lock lock(mutex_);
        const uint32_t   bytes   = static_cast<uint32_t>(sizeof(T)) * count;
        const auto [offset, ptr] = allocateStorageLocked(bytes, static_cast<uint32_t>(alignof(T)), true);
        return {offset, reinterpret_cast<T*>(ptr)};
    }

    template<typename T>
    uint32_t add(const T& value)
    {
        std::unique_lock lock(mutex_);
        const auto [offset, ptr] = allocateStorageLocked(static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)), false);
        if constexpr (std::is_trivially_copyable_v<T>)
        {
            std::memcpy(ptr, &value, sizeof(T));
        }
        else
        {
            std::construct_at(reinterpret_cast<T*>(ptr), value);
        }
        return offset;
    }

    template<class T>
    T* ptr(Ref ref) noexcept
    {
        const std::shared_lock lock(mutex_);
        return reinterpret_cast<T*>(findPtrLocked(ref, static_cast<uint32_t>(sizeof(T))));
    }

    template<class T>
    const T* ptr(Ref ref) const noexcept
    {
        const std::shared_lock lock(mutex_);
        return reinterpret_cast<const T*>(findPtrLocked(ref, static_cast<uint32_t>(sizeof(T))));
    }

private:
    uint32_t                                                               currentExtentLocked() const noexcept;
    std::pair<uint32_t, std::byte*>                                        allocateStorageLocked(uint32_t size, uint32_t align, bool zeroInit);
    std::byte*                                                             findPtrLocked(Ref ref, uint32_t size) noexcept;
    const std::byte*                                                       findPtrLocked(Ref ref, uint32_t size) const noexcept;
    Ref                                                                    findLargeBlockRefLocked(const void* ptr) const noexcept;
    void                                                                   recordAllocation(uint32_t offset, uint32_t size, uint32_t align);
    PagedStore                                                             store_;
    std::vector<LargeBlock>                                                largeBlocks_;
    std::unordered_map<std::string, std::pair<std::string_view, uint32_t>> stringMap_;
    std::vector<DataSegmentRelocation>                                     relocations_;
    std::vector<DataSegmentAllocation>                                     allocations_;
    mutable std::shared_mutex                                              mutex_;
};

SWC_END_NAMESPACE();
