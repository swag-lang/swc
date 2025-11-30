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
    {
        std::shared_lock lk(mutex_);
        if (const auto it = map_.find(value); it != map_.end())
            return it->second;
    }

    std::unique_lock lk(mutex_);
    if (const auto it = map_.find(value); it != map_.end())
        return it->second;

#if SWC_HAS_STATS
    Stats::get().numConstants.fetch_add(1);
    Stats::get().memConstants.fetch_add(sizeof(ConstantValue), std::memory_order_relaxed);
#endif

    if (value.isString())
    {
        auto [itStr, _] = cacheStr_.insert(std::string(value.getString()));
        auto stored     = ConstantValue::makeString(ctx, std::string_view(itStr->data(), itStr->size()));

        const ConstantRef ref{store_.push_back(stored) / static_cast<uint32_t>(sizeof(ConstantValue))};
        map_.emplace(stored, ref);
        return ref;
    }

    const ConstantRef ref{store_.push_back(value) / static_cast<uint32_t>(sizeof(ConstantValue))};
    map_.emplace(value, ref);
    return ref;
}

const ConstantValue& ConstantManager::get(ConstantRef constantRef) const
{
    SWC_ASSERT(constantRef.isValid());
    return *store_.ptr<ConstantValue>(constantRef.get() * sizeof(ConstantValue));
}

SWC_END_NAMESPACE()
