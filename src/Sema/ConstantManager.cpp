#include "pch.h"
#include "Sema/ConstantManager.h"
#include "Main/Stats.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

void ConstantManager::setup(const TaskContext& ctx)
{
    boolTrue_  = addConstant(ApValue::makeBool(ctx, true));
    boolFalse_ = addConstant(ApValue::makeBool(ctx, false));
}

ConstantRef ConstantManager::addConstant(const ApValue& value)
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
    Stats::get().memConstants.fetch_add(sizeof(ApValue), std::memory_order_relaxed);
#endif

    if (value.isString())
    {
        ApValue stored     = value;
        auto [itStr, _]    = cacheStr_.insert(std::string(value.getString()));
        stored.string_.val = std::string_view(itStr->data(), itStr->size());
        const ConstantRef ref{store_.push_back(stored)};
        map_.emplace(stored, ref);
        return ref;
    }

    const ConstantRef ref{store_.push_back(value)};
    map_.emplace(value, ref);
    return ref;
}

const ApValue& ConstantManager::get(ConstantRef constantRef) const
{
    std::shared_lock lk(mutex_);
    SWC_ASSERT(constantRef.isValid());
    return *store_.ptr<ApValue>(constantRef.get());
}

SWC_END_NAMESPACE()
