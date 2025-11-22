#include "pch.h"
#include "Sema/ConstantManager.h"
#include "Main/Stats.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

void ConstantManager::setup(const TaskContext& ctx)
{
    boolTrue_  = addConstant(ConstantValue::makeBool(ctx, true));
    boolFalse_ = addConstant(ConstantValue::makeBool(ctx, false));
}

ConstantRef ConstantManager::addConstant(const ConstantValue& value)
{
    {
        std::shared_lock lk(mutex_);
        const auto       it = map_.find(value);
        if (it != map_.end())
            return it->second;
    }

    std::unique_lock lk(mutex_);
    const auto [it, inserted] = map_.try_emplace(value, ConstantRef{});
    if (!inserted)
        return it->second;

#if SWC_HAS_STATS
    Stats::get().numConstants.fetch_add(1);
    Stats::get().memConstants.fetch_add(sizeof(ConstantValue), std::memory_order_relaxed);
#endif

    if (value.isString())
    {
        const auto str = cacheStr_.insert(std::string(value.getString()));
        auto       cpy = value;
        cpy.value()    = str.first->data();
        const ConstantRef ref{store_.push_back(cpy)};
        it->second = ref;
        return ref;
    }

    const ConstantRef ref{store_.push_back(value)};
    it->second = ref;
    return ref;
}

const ConstantValue& ConstantManager::get(ConstantRef constantRef) const
{
    std::shared_lock lk(mutex_);
    SWC_ASSERT(constantRef.isValid());
    return *store_.ptr<ConstantValue>(constantRef.get());
}

SWC_END_NAMESPACE()
