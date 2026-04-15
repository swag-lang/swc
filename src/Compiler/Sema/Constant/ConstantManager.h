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
    std::string_view addString(const TaskContext& ctx, std::string_view str);
    ConstantRef      addConstant(const TaskContext& ctx, const ConstantValue& value);
    // Fresh materialized payloads already live in a DataSegment and cannot be deduplicated by the pointer-identity map.
    ConstantRef      addMaterializedPayloadConstant(const ConstantValue& value);
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

    struct Shard
    {
        DataSegment                                                       dataSegment;
        std::unordered_map<ConstantValue, ConstantRef, ConstantValueHash> map;
        std::unordered_map<TypeRef, ConstantRef>                          typeInfoMap;
        mutable std::shared_mutex                                         mutex;
        mutable std::shared_mutex                                         typeInfoMutex;
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
