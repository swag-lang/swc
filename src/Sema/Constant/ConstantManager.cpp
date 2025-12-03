#include "pch.h"
#include "Sema/Constant/ConstantManager.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

void ConstantManager::setup(const TaskContext& ctx)
{
    cstBool_true_  = addConstant(ctx, ConstantValue::makeBool(ctx, true));
    cstBool_false_ = addConstant(ctx, ConstantValue::makeBool(ctx, false));
    cstS32_0_      = addConstant(ctx, ConstantValue::makeInt(ctx, ApsInt(0), 32));
    cstS32_1_      = addConstant(ctx, ConstantValue::makeInt(ctx, ApsInt(1), 32));
    cstS32_neg1_   = addConstant(ctx, ConstantValue::makeInt(ctx, ApsInt(-1), 32));
}

ConstantRef ConstantManager::cstS32(int32_t value) const
{
    switch (value)
    {
        case -1:
            return cstS32_neg1_;
        case 0:
            return cstS32_0_;
        case 1:
            return cstS32_1_;
        default:
            SWC_UNREACHABLE();
    }
}

ConstantRef ConstantManager::addConstant(const TaskContext& ctx, const ConstantValue& value)
{
    const uint32_t crc        = value.hash();
    const uint32_t shardIndex = crc % SHARD_COUNT;
    auto&          shard      = shards_[shardIndex];

    {
        std::shared_lock lk(shard.mutex);
        if (const auto it = shard.map.find(value); it != shard.map.end())
            return it->second;
    }

    std::unique_lock lk(shard.mutex);
    if (const auto it = shard.map.find(value); it != shard.map.end())
        return it->second;

#if SWC_HAS_STATS
    Stats::get().numConstants.fetch_add(1);
    Stats::get().memConstants.fetch_add(sizeof(ConstantValue), std::memory_order_relaxed);
#endif

    const uint32_t localIndex = shard.store.size() / sizeof(ConstantValue);
    SWC_ASSERT(localIndex <= LOCAL_MASK);

    if (value.isString())
    {
        auto [itStr, _]     = shard.cacheStr.insert(std::string(value.getString()));
        const auto strValue = ConstantValue::makeString(ctx, std::string_view(itStr->data(), itStr->size()));
        shard.store.push_back(strValue);
        ConstantRef ref{(shardIndex << LOCAL_BITS) | localIndex};
        shard.map.emplace(strValue, ref);
        return ref;
    }

    shard.store.push_back(value);
    ConstantRef ref{(shardIndex << LOCAL_BITS) | localIndex};
    shard.map.emplace(value, ref);
    return ref;
}

const ConstantValue& ConstantManager::get(ConstantRef constantRef) const
{
    SWC_ASSERT(constantRef.isValid());
    const auto shardIndex = constantRef.get() >> LOCAL_BITS;
    const auto localIndex = constantRef.get() & LOCAL_MASK;
    return *shards_[shardIndex].store.ptr<ConstantValue>(localIndex * sizeof(ConstantValue));
}

SWC_END_NAMESPACE()
