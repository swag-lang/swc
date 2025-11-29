#include "pch.h"
#include "Sema/ConstantManager.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

void ConstantManager::setup(const TaskContext& ctx)
{
    cstBool_true_  = addConstant(ctx, ConstantValue::makeBool(ctx, true));
    cstBool_false_ = addConstant(ctx, ConstantValue::makeBool(ctx, false));
    cstInt32_0_    = addConstant(ctx, ConstantValue::makeInt(ctx, ApsInt(0), 32));
    cstInt32_1_    = addConstant(ctx, ConstantValue::makeInt(ctx, ApsInt(1), 32));
    cstInt32_neg1_ = addConstant(ctx, ConstantValue::makeInt(ctx, ApsInt(-1), 32));
}

ConstantRef ConstantManager::cstS32(const TaskContext& ctx, int32_t value)
{
    switch (value)
    {
        case -1:
            return cstInt32_neg1_;
        case 0:
            return cstInt32_0_;
        case 1:
            return cstInt32_1_;
        default:
            return addConstant(ctx, ConstantValue::makeInt(ctx, ApsInt(value, false), 32));
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

        const ConstantRef ref{store_.push_back(stored)};
        map_.emplace(stored, ref);
        return ref;
    }

    const ConstantRef ref{store_.push_back(value)};
    map_.emplace(value, ref);
    return ref;
}

const ConstantValue& ConstantManager::get(ConstantRef constantRef) const
{
    std::shared_lock lk(mutex_);
    SWC_ASSERT(constantRef.isValid());
    return *store_.ptr<ConstantValue>(constantRef.get());
}

SWC_END_NAMESPACE()
