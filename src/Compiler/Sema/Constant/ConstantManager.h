#pragma once
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Support/Core/DataSegment.h"
#include <array>
#include <atomic>

SWC_BEGIN_NAMESPACE();
class CompilerInstance;

class ConstantManager
{
public:
    ConstantManager();

    void             setup(const TaskContext& ctx);
    ConstantRef      addS32(const TaskContext& ctx, int32_t value);
    ConstantRef      addInt(const TaskContext& ctx, uint64_t value);
    ConstantRef      addZeroPayloadConstant(TaskContext& ctx, TypeRef typeRef);
    std::string_view addString(const TaskContext& ctx, std::string_view str);
    ConstantRef      addConstant(const TaskContext& ctx, const ConstantValue& value);
    ConstantRef      addMaterializedPayloadConstant(const ConstantValue& value);
    ConstantRef      addUniqueMaterializedPayloadConstant(const ConstantValue& value);
    std::string_view addPayloadBuffer(std::string_view payload, DataSegmentRef* outRef = nullptr);

    ConstantRef          cstNull() const { return cstNull_; }
    ConstantRef          cstUndefined() const { return cstUndefined_; }
    ConstantRef          cstTrue() const { return cstBool_true_; }
    ConstantRef          cstFalse() const { return cstBool_false_; }
    ConstantRef          cstBool(bool value) const { return value ? cstBool_true_ : cstBool_false_; }
    ConstantRef          cstS32(int32_t value) const;
    ConstantRef          cstNegBool(ConstantRef cstRef) const { return cstRef == cstBool_true_ ? cstBool_false_ : cstBool_true_; }
    const ConstantValue& get(ConstantRef constantRef) const;
    Result               makeTypeInfo(Sema& sema, ConstantRef& outRef, TypeRef typeRef, AstNodeRef ownerNodeRef);
    TypeRef              makeTypeValue(Sema& sema, ConstantRef cstRef) const;
    DataSegment&         shardDataSegment(uint32_t index);
    const DataSegment&   shardDataSegment(uint32_t index) const;
    bool                 resolveDataSegmentRef(DataSegmentRef& outRef, const void* ptr) const noexcept;
    bool                 resolveConstantDataSegmentRef(DataSegmentRef& outRef, ConstantRef cstRef, const void* ptr) const noexcept;
    uint32_t             runtimeBufferConstantCacheShard(TypeRef typeRef, const void* targetPtr, uint64_t count) const;
    ConstantRef          findRuntimeBufferConstant(uint32_t shardIndex, TypeRef typeRef, const void* targetPtr, uint64_t count) const;
    ConstantRef          publishRuntimeBufferConstant(uint32_t shardIndex, TypeRef typeRef, const void* targetPtr, uint64_t count, ConstantRef cstRef);
    uint32_t             runtimeStringConstantCacheShard(TypeRef typeRef, std::string_view value) const;
    ConstantRef          findRuntimeStringConstant(uint32_t shardIndex, TypeRef typeRef, std::string_view value) const;
    ConstantRef          publishRuntimeStringConstant(uint32_t shardIndex, TypeRef typeRef, std::string_view value, ConstantRef cstRef);

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

        bool operator==(const RuntimeStringConstantCacheKey& rhs) const noexcept { return typeRef == rhs.typeRef && value == rhs.value; }
    };

    struct RuntimeStringConstantCacheKeyHash
    {
        size_t operator()(const RuntimeStringConstantCacheKey& key) const noexcept
        {
            size_t h = std::hash<uint32_t>{}(key.typeRef.get());
            h ^= std::hash<Utf8>{}(key.value) + 0x9e3779b97f4a7c15ull + (h << 6) + (h >> 2);
            return h;
        }
    };

    static constexpr uint32_t INTERN_STRIPE_BITS  = 4;
    static constexpr uint32_t INTERN_STRIPE_COUNT = 1u << INTERN_STRIPE_BITS;

    struct InternStripe
    {
        std::unordered_map<ConstantValue, ConstantRef, ConstantValueHash> map;
        mutable std::shared_mutex                                         mutex;
    };

    struct Shard
    {
        DataSegment                                                                                       dataSegment;
        std::array<InternStripe, INTERN_STRIPE_COUNT>                                                     internStripes;
        std::unordered_map<TypeRef, ConstantRef>                                                          typeInfoMap;
        std::unordered_map<TypeRef, ConstantRef>                                                          zeroPayloadMap;
        std::unordered_map<RuntimeBufferConstantCacheKey, ConstantRef, RuntimeBufferConstantCacheKeyHash> runtimeBufferMap;
        std::unordered_map<RuntimeStringConstantCacheKey, ConstantRef, RuntimeStringConstantCacheKeyHash> runtimeStringMap;
        mutable std::shared_mutex                                                                         typeInfoMutex;
        mutable std::shared_mutex                                                                         zeroPayloadMutex;
        mutable std::shared_mutex                                                                         runtimeBufferMutex;
        mutable std::shared_mutex                                                                         runtimeStringMutex;
    };

    static constexpr uint32_t SHARD_BITS  = 4;
    static constexpr uint32_t SHARD_COUNT = 1u << SHARD_BITS;
    static constexpr uint32_t LOCAL_BITS  = 32 - SHARD_BITS;
    static constexpr uint32_t LOCAL_MASK  = (1u << LOCAL_BITS) - 1;

private:
    ConstantRef        addConstantSlow(const TaskContext& ctx, const ConstantValue& value);
    ConstantRef        cachedS32(int32_t value) const;
    ConstantRef        constantRefFromRaw(uint32_t raw) const;
    ConstantRef        publishSmallScalarCache(uint32_t cacheIndex, ConstantRef cstRef);
    static ConstantRef publishTypeInfoCache(Shard& shard, TypeRef typeRef, ConstantRef cstRef);
    ConstantRef        tryGetBuiltinConstant(const TaskContext& ctx, const ConstantValue& value) const;
    ConstantRef        tryGetSmallScalarCache(uint32_t cacheIndex) const;
    static ConstantRef tryGetTypeInfoCache(const Shard& shard, TypeRef typeRef);
    uint32_t           zeroPayloadConstantCacheShard(TypeRef typeRef) const;
    ConstantRef        findZeroPayloadConstant(uint32_t shardIndex, TypeRef typeRef) const;
    ConstantRef        publishZeroPayloadConstant(uint32_t shardIndex, TypeRef typeRef, ConstantRef cstRef);
    bool               smallScalarCacheIndex(uint32_t& outIndex, const TaskContext& ctx, const ConstantValue& value) const;
    static uint32_t    smallIntTypeIndex(const TaskContext& ctx, TypeRef typeRef);

    static constexpr int32_t  SMALL_INT_MIN          = -128;
    static constexpr int32_t  SMALL_INT_MAX          = 1024;
    static constexpr uint32_t SMALL_INT_RANGE        = SMALL_INT_MAX - SMALL_INT_MIN + 1;
    static constexpr uint32_t SMALL_INT_TYPE_COUNT   = 11;
    static constexpr uint32_t SMALL_SCALAR_CACHE_LEN = SMALL_INT_TYPE_COUNT * SMALL_INT_RANGE;

    Shard                                                     shards_[SHARD_COUNT];
    std::array<std::atomic<uint32_t>, SMALL_SCALAR_CACHE_LEN> smallScalarRefs_;

    ConstantRef cstBool_true_  = ConstantRef::invalid();
    ConstantRef cstBool_false_ = ConstantRef::invalid();
    ConstantRef cstS32_0_      = ConstantRef::invalid();
    ConstantRef cstS32_1_      = ConstantRef::invalid();
    ConstantRef cstS32_neg1_   = ConstantRef::invalid();
    ConstantRef cstNull_       = ConstantRef::invalid();
    ConstantRef cstUndefined_  = ConstantRef::invalid();
};

SWC_END_NAMESPACE();
