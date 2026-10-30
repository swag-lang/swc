#pragma once
#include "Compiler/Sema/Constant/ConstantStorageLayout.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Support/Core/DataSegment.h"
#include "Support/Core/PointerSet.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class CompilerInstance;
class Sema;
class TaskContext;

namespace Runtime
{
    struct SourceCodeLocation;
}

class ConstantManager
{
public:
    enum class TypeInfoLockMode : uint8_t
    {
        Wait,
        TryLock,
    };

    ConstantManager();
    ~ConstantManager();

    void setup(const TaskContext& ctx);

    ConstantRef      addS32(const TaskContext& ctx, int32_t value);
    ConstantRef      addInt(const TaskContext& ctx, uint64_t value);
    ConstantRef      addZeroPayloadConstant(TaskContext& ctx, TypeRef typeRef);
    std::string_view addString(const TaskContext& ctx, std::string_view str);

    ConstantRef addConstant(const TaskContext& ctx, const ConstantValue& value);
    ConstantRef addMaterializedPayloadConstant(const ConstantValue& value);
    ConstantRef addUniqueMaterializedPayloadConstant(const ConstantValue& value);

    ConstantRef addSourceCodeLocation(const TaskContext& ctx, TypeRef typeRef, const Runtime::SourceCodeLocation& location);

    std::string_view addPayloadBuffer(std::string_view payload, DataSegmentRef* outRef = nullptr);
    // Use this overload when the payload consumer requires a specific alignment.
    std::string_view addPayloadBuffer(std::string_view payload, DataSegmentRef* outRef, uint32_t align);

    const std::byte* floatSignMask(bool is64, DataSegmentRef& outRef) const;

    ConstantRef cstNull() const { return cstNull_; }
    ConstantRef cstTrue() const { return cstBool_true_; }
    ConstantRef cstFalse() const { return cstBool_false_; }
    ConstantRef cstBool(bool value) const { return value ? cstBool_true_ : cstBool_false_; }
    ConstantRef cstS32(int32_t value) const;
    ConstantRef cstNegBool(ConstantRef cstRef) const { return cstRef == cstBool_true_ ? cstBool_false_ : cstBool_true_; }

    const ConstantValue& get(ConstantRef constantRef) const;

    Result  makeTypeInfo(Sema& sema, ConstantRef& outRef, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeInfoLockMode lockMode = TypeInfoLockMode::Wait);
    TypeRef makeTypeValue(Sema& sema, ConstantRef cstRef) const;

    DataSegment&       shardDataSegment(uint32_t index);
    const DataSegment& shardDataSegment(uint32_t index) const;

    // Shard relocation versions only grow, so their sum invalidates on any new relocation
    // without the shared writes required by a process-wide counter.
    uint64_t relocationVersionSum() const noexcept;

    bool resolveDataSegmentRef(DataSegmentRef& outRef, const void* ptr) const noexcept;
    bool hasUnpublishedFunctionRelocations(std::span<const DataSegmentRef> roots) const;
    bool resolveConstantDataSegmentRef(DataSegmentRef& outRef, ConstantRef cstRef, const void* ptr) const noexcept;

    DataSegmentRef findConstantStorage(ConstantRef cstRef, TypeRef storageTypeRef) const;
    DataSegmentRef publishConstantStorage(ConstantRef cstRef, TypeRef storageTypeRef, DataSegmentRef dataRef);

    static uint32_t runtimeBufferConstantCacheShard(TypeRef typeRef, const void* targetPtr, uint64_t count);
    ConstantRef     findRuntimeBufferConstant(uint32_t shardIndex, TypeRef typeRef, const void* targetPtr, uint64_t count) const;
    ConstantRef     publishRuntimeBufferConstant(uint32_t shardIndex, TypeRef typeRef, const void* targetPtr, uint64_t count, ConstantRef cstRef);

    static uint32_t runtimeStringConstantCacheShard(TypeRef typeRef, std::string_view value);
    ConstantRef     findRuntimeStringConstant(uint32_t shardIndex, TypeRef typeRef, std::string_view value) const;
    ConstantRef     publishRuntimeStringConstant(uint32_t shardIndex, TypeRef typeRef, std::string_view value, ConstantRef cstRef);

    // Cache an allocation and its relocations by segment version. Sema, publication
    // checks and JIT patching revisit the same constant graph thousands of times;
    // reuse avoids locking, searching and copying unchanged allocation metadata.
    struct WalkedAllocation
    {
        uint64_t relocationVersion = std::numeric_limits<uint64_t>::max();

        DataSegmentAllocation                 allocation;
        SmallVector<DataSegmentRelocation, 4> relocations;

        // Zero until the whole graph is proved data-only, then its relocation version sum.
        // Most constants contain no function pointers and need no JIT patch walk.
        mutable uint64_t dataOnlyRelocationVersions = 0;
    };

    // Per-thread entry owned by this manager, refreshed when relocation versions change.
    // Null if no allocation contains it. Other lookups preserve its address; only
    // another lookup of this same shard/offset can replace its contents.
    const WalkedAllocation* walkedAllocation(uint32_t shardIndex, uint32_t offset) const;

    struct RuntimeBufferConstantCacheKey
    {
        TypeRef   typeRef;
        uintptr_t targetPtr = 0;
        uint64_t  count     = 0;

        bool operator==(const RuntimeBufferConstantCacheKey& rhs) const noexcept { return typeRef == rhs.typeRef && targetPtr == rhs.targetPtr && count == rhs.count; }
    };

    struct RuntimeBufferConstantCacheKeyHash
    {
        size_t operator()(const RuntimeBufferConstantCacheKey& key) const noexcept
        {
            size_t h = std::hash<uint32_t>{}(key.typeRef.get());
            h ^= std::hash<uintptr_t>{}(key.targetPtr) + 0x9e3779b97f4a7c15ull + (h << 6) + (h >> 2);
            h ^= std::hash<uint64_t>{}(key.count) + 0x9e3779b97f4a7c15ull + (h << 6) + (h >> 2);
            return h;
        }
    };

    struct RuntimeStringConstantCacheKey
    {
        TypeRef typeRef;
        Utf8    value;
    };

    struct RuntimeStringConstantCacheLookupKey
    {
        TypeRef          typeRef;
        std::string_view value;
    };

    struct RuntimeStringConstantCacheKeyHash
    {
        using is_transparent = void;

        static size_t hash(TypeRef typeRef, std::string_view value) noexcept
        {
            size_t h = std::hash<uint32_t>{}(typeRef.get());
            h ^= std::hash<std::string_view>{}(value) + 0x9e3779b97f4a7c15ull + (h << 6) + (h >> 2);
            return h;
        }

        size_t operator()(const RuntimeStringConstantCacheKey& key) const noexcept
        {
            return hash(key.typeRef, key.value.view());
        }

        size_t operator()(const RuntimeStringConstantCacheLookupKey& key) const noexcept { return hash(key.typeRef, key.value); }
    };

    struct RuntimeStringConstantCacheKeyEqual
    {
        using is_transparent = void;

        bool operator()(const RuntimeStringConstantCacheKey& lhs, const RuntimeStringConstantCacheKey& rhs) const noexcept { return lhs.typeRef == rhs.typeRef && lhs.value == rhs.value; }
        bool operator()(const RuntimeStringConstantCacheKey& lhs, const RuntimeStringConstantCacheLookupKey& rhs) const noexcept { return lhs.typeRef == rhs.typeRef && lhs.value.view() == rhs.value; }
        bool operator()(const RuntimeStringConstantCacheLookupKey& lhs, const RuntimeStringConstantCacheKey& rhs) const noexcept { return lhs.typeRef == rhs.typeRef && lhs.value == rhs.value.view(); }
    };

    static constexpr uint32_t INTERN_STRIPE_BITS  = 4;
    static constexpr uint32_t INTERN_STRIPE_COUNT = 1u << INTERN_STRIPE_BITS;

    struct StoredConstantDeleter
    {
        // The segment owns the bytes; the intern table owns the aggregate payload's lifetime.
        void operator()(ConstantValue* value) const noexcept { std::destroy_at(value); }
    };

    using StoredConstant = std::unique_ptr<ConstantValue, StoredConstantDeleter>;

    // Open-addressed and append-only: a slot, once filled, keeps its constant. Readers probe it
    // without a lock; writers fill it under the stripe mutex, hash and reference before value.
    // Identity never reads the enriched data-segment location, the one field written in place.
    struct InternTable
    {
        std::unique_ptr<std::atomic<const ConstantValue*>[]> values;
        std::unique_ptr<std::atomic<uint32_t>[]>             hashes;
        std::unique_ptr<std::atomic<uint32_t>[]>             refs;

        uint32_t capacity = 0; // power of two
        uint32_t size     = 0; // writer-only
    };

    // Give each stripe its own cache line. owned retains canonical values; readers
    // probe table without locking while writers hold mutex. Keep all table generations
    // alive with the stripe so readers can finish probing older ones.
    struct alignas(64) InternStripe
    {
        std::vector<StoredConstant> owned;

        std::atomic<InternTable*>                 table = nullptr;
        std::vector<std::unique_ptr<InternTable>> tables;

        std::mutex mutex; // writers only
    };

    // Canonical string offsets, the type and all four coordinates determine the complete
    // immutable location, including its relocation graph. Raw payload interning cannot do this.
    using SourceLocationKey = std::array<uint32_t, 7>;
    struct SourceLocationKeyHash
    {
        size_t operator()(const SourceLocationKey& key) const noexcept;
    };

    struct Shard
    {
        // Keep storage alive until the intern tables have destroyed their canonical values.
        DataSegment dataSegment;

        std::array<InternStripe, INTERN_STRIPE_COUNT> internStripes;

        FlatKeyMap<ConstantRef>              typeInfoMap;
        FlatKeyMap<ConstantRef>              zeroPayloadMap;
        FlatKeyMap<DataSegmentRef, uint64_t> constantStorageMap;

        std::unordered_map<RuntimeBufferConstantCacheKey, ConstantRef, RuntimeBufferConstantCacheKeyHash> runtimeBufferMap;

        std::unordered_map<RuntimeStringConstantCacheKey, ConstantRef, RuntimeStringConstantCacheKeyHash, RuntimeStringConstantCacheKeyEqual> runtimeStringMap;

        std::unordered_map<SourceLocationKey, ConstantRef, SourceLocationKeyHash> sourceLocationMap;

        std::mutex                sourceLocationMutex;
        mutable std::shared_mutex typeInfoMutex;
        mutable std::shared_mutex zeroPayloadMutex;
        mutable std::shared_mutex constantStorageMutex;
        mutable std::shared_mutex runtimeBufferMutex;
        mutable std::shared_mutex runtimeStringMutex;
    };

private:
    struct WalkedAllocations;
    WalkedAllocations& walkedAllocations() const;

    ConstantRef        addConstantSlow(const TaskContext& ctx, const ConstantValue& value);
    ConstantRef        cachedS32(int32_t value) const;
    ConstantRef        constantRefFromRaw(uint32_t raw) const;
    ConstantRef        publishSmallScalarCache(uint32_t cacheIndex, ConstantRef cstRef);
    static ConstantRef publishTypeInfoCache(Shard& shard, TypeRef typeRef, ConstantRef cstRef);
    ConstantRef        tryGetBuiltinConstant(const TaskContext& ctx, const ConstantValue& value) const;
    ConstantRef        tryGetSmallScalarCache(uint32_t cacheIndex) const;
    static ConstantRef tryGetTypeInfoCache(const Shard& shard, TypeRef typeRef);

    static uint32_t zeroPayloadConstantCacheShard(TypeRef typeRef);
    ConstantRef     findZeroPayloadConstant(uint32_t shardIndex, TypeRef typeRef) const;
    ConstantRef     publishZeroPayloadConstant(uint32_t shardIndex, TypeRef typeRef, ConstantRef cstRef);

    bool            smallScalarCacheIndex(uint32_t& outIndex, const TaskContext& ctx, const ConstantValue& value) const;
    static uint32_t smallIntTypeIndex(const TaskContext& ctx, TypeRef typeRef);

    static constexpr int32_t  SMALL_INT_MIN          = -128;
    static constexpr int32_t  SMALL_INT_MAX          = 1024;
    static constexpr uint32_t SMALL_INT_RANGE        = SMALL_INT_MAX - SMALL_INT_MIN + 1;
    static constexpr uint32_t SMALL_INT_TYPE_COUNT   = 11;
    static constexpr uint32_t SMALL_SCALAR_CACHE_LEN = SMALL_INT_TYPE_COUNT * SMALL_INT_RANGE;

    Shard shards_[ConstantStorageLayout::SHARD_COUNT];

    mutable std::mutex                                      walkedAllocationsMutex_;
    mutable std::vector<std::unique_ptr<WalkedAllocations>> walkedAllocations_;

    std::array<std::atomic<uint32_t>, SMALL_SCALAR_CACHE_LEN> smallScalarRefs_;

    ConstantRef cstBool_true_  = ConstantRef::invalid();
    ConstantRef cstBool_false_ = ConstantRef::invalid();
    ConstantRef cstS32_0_      = ConstantRef::invalid();
    ConstantRef cstS32_1_      = ConstantRef::invalid();
    ConstantRef cstS32_neg1_   = ConstantRef::invalid();
    ConstantRef cstNull_       = ConstantRef::invalid();

    const std::byte* floatSignMask32_ = nullptr;
    const std::byte* floatSignMask64_ = nullptr;
    DataSegmentRef   floatSignMaskRef32_;
    DataSegmentRef   floatSignMaskRef64_;
};

SWC_END_NAMESPACE();
