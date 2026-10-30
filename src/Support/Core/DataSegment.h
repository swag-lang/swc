#pragma once
#include "Support/Core/PagedStore.h"
#include "Support/Core/SmallVector.h"
#include "Support/Core/StringMap.h"
#include "Support/Core/Utf8.h"
#include "Support/Memory/Arena.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

enum class DataSegmentKind : uint8_t
{
    Zero,
    GlobalZero,
    GlobalInit,
    Compiler,
};

enum class DataSegmentRelocationKind : uint8_t
{
    DataSegmentOffset,
    FunctionSymbol,
};

struct DataSegmentRelocation
{
    uint32_t                  offset                  = 0;
    DataSegmentRelocationKind kind                    = DataSegmentRelocationKind::DataSegmentOffset;
    bool                      allowUnresolvedFunction = false;

    uint32_t targetOffset     = INVALID_REF;
    uint32_t targetShardIndex = INVALID_REF;

    const SymbolFunction* targetSymbol = nullptr;
};

struct DataSegmentAllocation
{
    uint32_t offset = 0;
    uint32_t size   = 0;
    uint32_t align  = 1;
};

struct DataSegmentRef
{
    uint32_t shardIndex = INVALID_REF;
    uint32_t offset     = INVALID_REF;

    bool isValid() const noexcept { return shardIndex != INVALID_REF && offset != INVALID_REF; }
    bool isInvalid() const noexcept { return !isValid(); }
};

class DataSegment
{
public:
    struct LargeBlockStorageDeleter
    {
        uint32_t proximitySize = 0;

        void operator()(std::byte* ptr) const noexcept;
    };
    using LargeBlockStorage = std::unique_ptr<std::byte[], LargeBlockStorageDeleter>;

    struct LargeBlock
    {
        uint32_t offset = 0;
        uint32_t size   = 0;

        LargeBlockStorage storage;
    };

    struct LargeBlockRange
    {
        uintptr_t offsetEnd   = 0;
        uint32_t  blockOffset = 0;
    };

    // Allocate this segment's payload (pages and large blocks) from the
    // proximity arena, so JIT code can reach it RIP-relative. Meant for the
    // mutable global segments; call before the segment grows.
    void enableProximityStorage() noexcept
    {
        store_.enableProximityPages();
        proximityStorage_ = true;
    }

    std::pair<std::span<const std::byte>, Ref> addSpan(std::span<const std::byte> value);
    std::pair<std::span<const std::byte>, Ref> addSpan(std::span<const std::byte> value, uint32_t align);
    std::pair<std::string_view, Ref>           addString(std::string_view value);
    uint32_t                                   addString(uint32_t baseOffset, uint32_t fieldOffset, std::string_view value);

    void addRelocation(uint32_t offset, uint32_t targetOffset);
    void addRelocation(uint32_t offset, DataSegmentRef targetRef);
    void addFunctionRelocation(uint32_t offset, const SymbolFunction* targetSymbol, bool allowUnresolvedFunction = false);

    // Add a relocation target at an absolute offset in this segment.
    void addRelocation(uint32_t offset, const DataSegmentRelocation& target)
    {
        if (target.kind == DataSegmentRelocationKind::FunctionSymbol)
            addFunctionRelocation(offset, target.targetSymbol, target.allowUnresolvedFunction);
        else
            addRelocation(offset, {.shardIndex = target.targetShardIndex, .offset = target.targetOffset});
    }

    std::pair<uint32_t, std::byte*> reserveBytes(uint32_t size, uint32_t align, bool zeroInit);
    uint32_t                        reserveBlock(uint32_t size, uint32_t align, bool zeroInit);

    Ref  findRef(const void* ptr) const noexcept;
    bool findAllocation(DataSegmentAllocation& outAllocation, uint32_t offset) const noexcept;
    // True when the allocation holds a string that addString interned: its owners can never
    // rely on a distinct address for equal content.
    bool isInternedString(const DataSegmentAllocation& allocation) const;

    uint32_t size() const noexcept;
    uint32_t extentSize() const noexcept;

    void copyTo(std::span<std::byte> dst) const;
    void copyToPreserveOffsets(std::span<std::byte> dst) const;
    void restoreFromPreserveOffsets(std::span<const std::byte> src) const;
    void fill(std::byte value) const;

    std::vector<DataSegmentRelocation> copyRelocations() const;
    // Copies only targets of function-symbol relocations, in relocation order.
    std::vector<const SymbolFunction*> copyFunctionRelocationTargets() const;
    // Copies data-segment targets with a shard index, in relocation order.
    std::vector<DataSegmentRef> copyDataSegmentRelocationTargets() const;

    // Identity of this segment, and how many relocations it has taken. Together they let a reader
    // remember what a given offset resolved to and know, in one comparison, whether that answer
    // can still be trusted.
    uint64_t id() const noexcept { return id_; }
    uint64_t relocationVersion() const noexcept { return relocationVersion_.load(std::memory_order_acquire); }

    void copyRelocations(std::vector<DataSegmentRelocation>& outRelocations, uint32_t offset, uint32_t size) const;
    void copyRelocations(SmallVector<DataSegmentRelocation, 4>& outRelocations, uint32_t offset, uint32_t size) const;
    bool findRelocation(DataSegmentRelocation& outRelocation, uint32_t offset, DataSegmentRelocationKind kind) const;
    bool hasRelocations(uint32_t offset, uint32_t size) const;

    std::mutex& allocationMutex(uint32_t allocationOffset) const;

    template<typename T>
    std::pair<uint32_t, T*> reserve()
    {
        std::unique_lock lock(mutex_);
        const auto [offset, ptr] = allocateStorageLocked(static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)), true);
        recordAllocation(offset, static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)));
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
        recordAllocation(offset, bytes, static_cast<uint32_t>(alignof(T)));
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

        recordAllocation(offset, static_cast<uint32_t>(sizeof(T)), static_cast<uint32_t>(alignof(T)));
        return offset;
    }

    template<class T>
    T* ptr(Ref ref) noexcept
    {
        return const_cast<T*>(std::as_const(*this).ptr<T>(ref));
    }

    template<class T>
    const T* ptr(Ref ref) const noexcept
    {
        // Fast path: when no large blocks have ever been allocated, the data lives entirely in
        // the underlying PagedStore, whose reads are lock-free (atomically-published page snapshot,
        // append-only storage). This avoids touching the per-segment shared_mutex on the hot read
        // path, which otherwise serializes against every interning add()/addSpan() on the segment.
        if (!hasLargeBlocks_.load(std::memory_order_acquire))
            return reinterpret_cast<const T*>(store_.ptr<std::byte>(ref));

        const std::shared_lock lock(mutex_);
        return reinterpret_cast<const T*>(findPtrLocked(ref, static_cast<uint32_t>(sizeof(T))));
    }

private:
    struct InternedString
    {
        const char* data   = nullptr;
        uint32_t    size   = 0;
        Ref         offset = INVALID_REF;
    };

    uint32_t                        currentExtentLocked() const noexcept;
    std::pair<uint32_t, std::byte*> allocateStorageLocked(uint32_t size, uint32_t align, bool zeroInit);
    const std::byte*                findPtrLocked(Ref ref, uint32_t size) const noexcept;
    Ref                             findLargeBlockRefLocked(const void* ptr) const noexcept;

    bool findRelocationLocked(DataSegmentRelocation& outRelocation, uint32_t offset, DataSegmentRelocationKind kind) const;
    bool hasRelocationsLocked(uint32_t offset, uint32_t size) const;
    void rebuildRelocationsByOffsetLocked() const;
    void recordRelocationIndexLocked(uint32_t index);

    void recordAllocation(uint32_t offset, uint32_t size, uint32_t align);

    template<typename T>
    void copyRelocationsImpl(T& outRelocations, uint32_t offset, uint32_t size) const;

    PagedStore                           store_;
    std::vector<LargeBlock>              largeBlocks_;
    std::map<uintptr_t, LargeBlockRange> largeBlockRanges_;

    // Keys are copied into their own arena: segment bytes can be restored by test snapshots.
    StringMap<InternedString> stringMap_;
    Arena                     stringKeys_{4 * 1024 - 64};

    static inline std::atomic<uint64_t> s_nextId{1};
    const uint64_t                      id_ = s_nextId.fetch_add(1, std::memory_order_relaxed);
    std::atomic<uint64_t>               relocationVersion_{0};

    std::vector<DataSegmentRelocation> relocations_;

    // Sorted-by-offset index over the first `relocationsIndexedCount_` relocations. Relocations beyond
    // that count form the tail, which carries its own index sorted the same way. Readers binary-search
    // both under a shared lock, so they never scan a growing tail and never escalate to an exclusive
    // rebuild; the tail is merged into the index on the writer side once it grows past a threshold.
    mutable std::vector<uint32_t> relocationsByOffset_;
    mutable std::vector<uint32_t> relocationsTailByOffset_;
    mutable uint32_t              relocationsIndexedCount_ = 0;

    std::vector<DataSegmentAllocation> allocations_;

    std::atomic<bool> hasLargeBlocks_{false};
    bool              proximityStorage_ = false;

    mutable std::shared_mutex mutex_;
    mutable std::shared_mutex relocationsMutex_;
    mutable std::shared_mutex allocationsMutex_;
    mutable std::mutex        allocationMutexesMutex_;

    mutable std::unordered_map<uint32_t, std::unique_ptr<std::mutex>> allocationMutexes_;
};

SWC_END_NAMESPACE();
